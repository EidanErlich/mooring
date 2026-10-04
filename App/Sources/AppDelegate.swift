import AppKit
@preconcurrency import AwaykeMonitors
import AwakeKit
import Defaults
import Observation
import os
import UserNotifications
import WindowKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: AwakeEngine?
    private var lid: LidController?
    private let battery = BatteryMonitor()
    private let lidMonitor = LidMonitor()
    private var thermalObserver: NSObjectProtocol?
    private var terminationReplied = false
    private var statusItemController: StatusItemController?
    private var dropdown: DropdownController?
    private var windows: WindowsController?
    private var clipboard: ClipboardController?
    private var tickTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var socketServer: SocketServer?
    private let approvals = LidApprovalCenter()
    private lazy var windowApprovals = WindowApprovalCenter(poster: poster)
    /// Agents' window arrangements, built when first needed while Windows is on and dropped (with its undo stack)
    /// when Windows stops.
    private var arranger: Arranger?
    private var notificationResponder: NotificationResponder?
    private var lidSettingUpdates: Task<Void, Never>?
    /// Posts `notify`'s notifications and link errors.
    private let poster = SystemNotificationPoster()
    /// Hands the handler to links and Shortcuts, which can arrive before it's built. It is the Shortcuts actions' own.
    private var gate: HandlerGate { IntentActions.shared.gate }
    private lazy var links = LinkHandler(
        gate: gate, poster: poster, appName: { NSRunningApplication(processIdentifier: $0)?.localizedName }
    )

    /// True when Xcode launched the app only to host unit tests.
    nonisolated static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Links are taken from here on, so one that launches the app isn't lost; it waits for the handler.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    /// A `mooring://` link. It never brings Mooring forward; the request runs in the background.
    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text) else { return }
        let senderPID = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        Task { await links.open(url, senderPID: senderPID) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A test host must not touch the user's real leases or assertions.
        guard !Self.isHostingTests else { return }

        let lid = LidController(helper: HelperClient.shared)
        let engine = AwakeEngine(
            assertions: IOPMAssertions(), store: FileLeaseStore(), processes: SystemProcesses(),
            lid: lid, settings: { Defaults[.awake] }
        )
        self.lid = lid
        self.engine = engine
        SettingsWindowController.shared.engine = engine
        SettingsWindowController.shared.lid = lid
        engine.onSuspensionsAdded = { [weak engine] added in
            let current = Date()
            let lidLeaseIDs = engine?.leases.filter { $0.level.lid && $0.isLive(at: current) }.map(\.id) ?? []
            GuardrailNotifier.post(added, lidLeaseIDs: lidLeaseIDs)
        }
        startNotificationResponses()
        startMonitors(engine)
        engine.restore()
        startSocketServer(engine)

        // The reconciler's backstop tick (docs/SPEC.md 1.2): drops expired leases.
        let timer = Timer(timeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { engine.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { engine.systemDidWake() }
        }

        // Off by default; starts only if enabled and trusted, and never asks for Accessibility here.
        let windows = WindowsController.live()
        windows.launch()
        self.windows = windows
        SettingsWindowController.shared.windows = windows
        observeWindowsForArranger()

        // Off by default; ClipKit isn't even created until Clipboard is turned on.
        let clipboard = ClipboardController.live()
        clipboard.launch()
        self.clipboard = clipboard

        let statusItem = StatusItemController(engine: engine, windows: windows)
        let dropdown = DropdownController(
            engine: engine, approvals: approvals, windows: windows,
            openSettings: { SettingsWindowController.shared.show() })
        statusItem.onOpenMenu = { [weak statusItem] in
            statusItem.map(dropdown.open(from:))
        }
        statusItemController = statusItem
        self.dropdown = dropdown
    }

    /// Battery, lid and thermal state feed the guardrails (docs/SPEC.md 1.7).
    private func startMonitors(_ engine: AwakeEngine) {
        battery.onChange = { snapshot in
            MainActor.assumeIsolated {
                engine.update(power: PowerSnapshot(onAC: snapshot.onAC, batteryPercent: snapshot.percent))
            }
        }
        battery.start()
        if let snapshot = battery.currentSnapshot() {
            engine.update(power: PowerSnapshot(onAC: snapshot.onAC, batteryPercent: snapshot.percent))
        }

        lidMonitor.onChange = { closed in
            MainActor.assumeIsolated { engine.update(lidClosed: closed) }
        }
        lidMonitor.start()
        engine.update(lidClosed: lidMonitor.isClosed)

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { engine.update(thermal: ProcessInfo.processInfo.thermalState) }
        }
        engine.update(thermal: ProcessInfo.processInfo.thermalState)
    }

    /// The arranger while Windows is on, built on first use over the live windows.
    private func currentArranger() -> Arranger? {
        guard windows?.state == .on else { return nil }
        if let arranger { return arranger }
        let made = Arranger(system: LiveWindowSystem(), layoutsURL: LayoutStore.defaultURL)
        arranger = made
        return made
    }

    /// Drops the arranger whenever Windows leaves on.
    private func observeWindowsForArranger() {
        withObservationTracking {
            _ = windows?.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.windows?.state != .on { self.arranger = nil }
                self.observeWindowsForArranger()
            }
        }
    }

    /// Registers the approval actions, removes approvals left from a previous
    /// run, and routes responses to the approval centers. Nothing is posted here;
    /// permission is asked on first need.
    private func startNotificationResponses() {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([LidApprovalCenter.category, WindowApprovalCenter.category])
        Task { [approvals, windowApprovals] in
            await approvals.removeStaleApprovals()
            await windowApprovals.removeStaleApprovals()
        }
        let responder = NotificationResponder(approvals: approvals, windowApprovals: windowApprovals)
        center.delegate = responder
        notificationResponder = responder
    }

    /// Serves the `mooring` CLI (docs/SPEC.md 2.1). Failing to listen leaves the menu working.
    private func startSocketServer(_ engine: AwakeEngine) {
        let handler = RequestHandler(
            engine: engine, settings: { Defaults[.awake] },
            helperStatus: { "\(HelperClient.shared.status)" },
            // A hung helper mustn't hang `mooring status`.
            readHelperSleepDisabled: {
                await withDeadline(.seconds(1)) { @MainActor in try? await HelperClient.shared.lidSleepDisabled() }
            },
            approver: approvals,
            updateSettings: { change in
                var settings = Defaults[.awake]
                change(&settings)
                Defaults[.awake] = settings
            },
            notificationStatus: { [approvals] in await approvals.notificationStatus() },
            poster: poster,
            windowsState: { [weak self] in self?.windows?.state ?? .off },
            arranger: { [weak self] in self?.currentArranger() },
            windowApprover: windowApprovals
        )
        gate.set(handler)
        // Never, or session lid switched off, takes lid mode back from live agent leases right away.
        lidSettingUpdates = Task {
            for await _ in Defaults.updates(.awake, initial: false) { handler.applyLidSettings() }
        }
        let server = SocketServer(path: SocketServer.defaultPath) { request, caller in
            await handler.handle(request, from: caller)
        }
        do {
            try server.start()
            socketServer = server
        } catch {
            Logger(subsystem: "dev.mooring", category: "ipc")
                .error("CLI socket unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
        clipboard?.willTerminate()
    }

    /// Never quit with lid sleep disabled (docs/SPEC.md 1.6, layer 4). The
    /// helper's watchdog covers the case where this doesn't finish in 3 s.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let lid, lid.applied == true || lid.isBusy else { return .terminateNow }
        Task { @MainActor in
            await lid.shutDown()
            self.replyToTermination()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            MainActor.assumeIsolated { self.replyToTermination() }
        }
        return .terminateLater
    }

    private func replyToTermination() {
        guard !terminationReplied else { return }
        terminationReplied = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }
}

/// Forwards notification responses to the approval centers. Tapping an
/// approval's body opens Settings → Agents; it and dismissal don't answer.
private final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    private let approvals: LidApprovalCenter
    private let windowApprovals: WindowApprovalCenter

    init(approvals: LidApprovalCenter, windowApprovals: WindowApprovalCenter) {
        self.approvals = approvals
        self.windowApprovals = windowApprovals
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let category = request.content.categoryIdentifier
        guard category == LidApprovalCenter.categoryID || category == WindowApprovalCenter.categoryID else {
            completionHandler()
            return
        }
        let action = response.actionIdentifier
        let requestID = request.identifier
        let (approvals, windowApprovals) = (approvals, windowApprovals)
        Task { @MainActor in
            if action == UNNotificationDefaultActionIdentifier {
                SettingsWindowController.shared.show(page: .agents)
            } else if category == WindowApprovalCenter.categoryID {
                windowApprovals.handle(actionIdentifier: action, requestID: requestID)
            } else {
                approvals.handle(actionIdentifier: action, requestID: requestID)
            }
        }
        completionHandler()
    }

    /// Shows banners even while Mooring is the active app (e.g. Settings is open).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

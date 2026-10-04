import AppKit
@preconcurrency import AwaykeMonitors
import AwakeKit
import Defaults
import os
import UserNotifications

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
    private var tickTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var socketServer: SocketServer?
    private let approvals = LidApprovalCenter()
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

        let statusItem = StatusItemController(engine: engine, windows: windows)
        let dropdown = DropdownController(engine: engine, approvals: approvals, openSettings: { SettingsWindowController.shared.show() })
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

    /// Registers the lid-approval actions, removes approvals left from a previous
    /// run, and routes responses to the approval center. Nothing is posted here;
    /// permission is asked on first need.
    private func startNotificationResponses() {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([LidApprovalCenter.category])
        Task { [approvals] in await approvals.removeStaleApprovals() }
        let responder = NotificationResponder(approvals: approvals)
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
            poster: poster
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

/// Forwards notification responses to the approval center. Tapping an
/// approval's body opens Settings → Agents; it and dismissal don't answer.
private final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    private let approvals: LidApprovalCenter

    init(approvals: LidApprovalCenter) {
        self.approvals = approvals
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        guard request.content.categoryIdentifier == LidApprovalCenter.categoryID else {
            completionHandler()
            return
        }
        let action = response.actionIdentifier
        let requestID = request.identifier
        let approvals = approvals
        Task { @MainActor in
            if action == UNNotificationDefaultActionIdentifier {
                SettingsWindowController.shared.show(page: .agents)
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

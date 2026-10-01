import AppKit
@preconcurrency import AwaykeMonitors
import AwakeKit
import Defaults

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
    private var tickTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    /// True when Xcode launched the app only to host unit tests.
    nonisolated static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
        startMonitors(engine)
        engine.restore()

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

        let statusItem = StatusItemController(engine: engine)
        let dropdown = DropdownController(engine: engine, openSettings: { SettingsWindowController.shared.show() })
        statusItem.onOpenPanel = { [weak statusItem] in
            guard let button = statusItem?.button else { return }
            dropdown.toggle(below: button)
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

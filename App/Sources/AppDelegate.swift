import AppKit
import AwakeKit
import Defaults

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: AwakeEngine?
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

        let engine = AwakeEngine(
            assertions: IOPMAssertions(), store: FileLeaseStore(), processes: SystemProcesses(),
            settings: { Defaults[.awake] }
        )
        engine.restore()
        self.engine = engine

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
}

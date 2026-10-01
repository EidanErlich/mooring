import AppKit
import AwakeKit
import Defaults

/// Owns Mooring's single menu-bar item: the icon (see MenuBarIcon) and click routing.
/// The item is as wide as its content, which only changes when what it shows changes.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine: AwakeEngine
    private var shown: String?
    private var countdown: Timer?
    private var settingUpdates: Task<Void, Never>?

    /// Called for the click that opens the dropdown.
    var onOpenPanel: (() -> Void)?

    var button: NSStatusBarButton? { statusItem.button }

    init(engine: AwakeEngine) {
        self.engine = engine
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refresh()
        settingUpdates = Task { [weak self] in
            for await _ in Defaults.updates(.showTimeLeftInMenuBar, initial: false) { self?.refresh() }
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let action = ClickRouter.action(
            isRightMouse: event?.type == .rightMouseUp,
            controlDown: event?.modifierFlags.contains(.control) == true,
            swapped: Defaults[.swapClickActions]
        )
        switch action {
        case .toggle: engine.toggleMenu()
        case .openPanel: onOpenPanel?()
        }
    }

    /// Redraws the icon when what it shows changed, and re-arms observation of the engine.
    private func refresh() {
        let menuState = withObservationTracking {
            MenuBarState.from(leases: engine.leases, state: engine.state, wantsLid: engine.wantsLid,
                              helperEnabled: HelperClient.shared.status == .enabled,
                              showTimeLeft: Defaults[.showTimeLeftInMenuBar], now: Date())
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        // The spoken sentence names everything the image shows, down to the visible minute.
        let sentence = MenuBarText.accessibilityLabel(for: menuState)
        if sentence != shown {
            shown = sentence
            statusItem.button?.image = MenuBarIcon.image(for: menuState)
            statusItem.button?.setAccessibilityLabel(sentence)
        }
        updateCountdown(for: menuState)
    }

    /// A visible countdown needs a periodic check; nothing else does.
    private func updateCountdown(for menuState: MenuBarState) {
        guard case .awake(_, .timed(_?)) = menuState else {
            countdown?.invalidate()
            countdown = nil
            return
        }
        guard countdown == nil else { return }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdown = timer
    }
}

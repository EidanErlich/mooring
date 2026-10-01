import AppKit
import AwakeKit
import Defaults

/// Owns Mooring's single menu-bar item: the anchor (filled while anything keeps
/// the Mac awake, with lid, battery and attention badges) and click routing.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let engine: AwakeEngine

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

    /// Redraws the icon and re-arms observation of the engine's state.
    private func refresh() {
        let menuState = withObservationTracking {
            MenuBarState.from(leases: engine.leases, state: engine.state, wantsLid: engine.wantsLid,
                              helperEnabled: HelperClient.shared.status == .enabled, showTimeLeft: true, now: Date())
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        statusItem.button?.image = MenuBarIcon.image(for: menuState)
        statusItem.button?.setAccessibilityLabel(MenuBarText.accessibilityLabel(for: menuState))
    }
}

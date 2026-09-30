import AppKit

/// Owns Mooring's single menu-bar item. Stage 0 shows the outline anchor and a
/// Quit menu; stage 1b replaces the menu with the dropdown panel. Debug builds
/// also show the stage 1a lid menu on right click or Control-click.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let quitMenu = StatusItemController.makeMenu()
    #if DEBUG
    private let debugMenu = DebugLidMenu(helper: .shared)
    #endif

    override init() {
        super.init()
        statusItem.button?.image = MenuBarIcon.image(filled: false)
        statusItem.button?.setAccessibilityLabel("Mooring")
        #if DEBUG
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        #else
        statusItem.menu = quitMenu
        #endif
    }

    private static func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit Mooring",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    #if DEBUG
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        show(isSecondary ? debugMenu.menu : quitMenu)
    }

    private func show(_ menu: NSMenu) {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    #endif
}

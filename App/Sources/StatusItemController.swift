import AppKit

/// Owns Mooring's single menu-bar item. Stage 0 shows the outline anchor and a
/// Quit menu; stage 1b replaces the menu with the dropdown panel.
@MainActor
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init() {
        statusItem.button?.image = MenuBarIcon.image(filled: false)
        statusItem.button?.setAccessibilityLabel("Mooring")
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit Mooring",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }
}

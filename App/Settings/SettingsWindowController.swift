import AppKit
import AwakeKit
import SwiftUI

/// The one Settings window, created on first use and reused after.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    /// Set once at launch, for the pages that read engine state (diagnostics).
    var engine: AwakeEngine?
    var lid: LidController?
    var windows: WindowsController?
    var clipboard: ClipboardController?
    var updates: UpdatesController?
    private let navigation = SettingsNavigation()

    private lazy var window: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mooring Settings"
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                engine: engine, windows: windows, clipboard: clipboard, updates: updates, navigation: navigation))
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 640, height: 420))
        window.center()
        return window
    }()

    /// How the window is brought forward; tests swap it so no window is shown.
    private let present: @MainActor (NSWindow) -> Void

    init(present: @escaping @MainActor (NSWindow) -> Void = { window in
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }) {
        self.present = present
    }

    var selectedPage: SettingsPage? { navigation.selection }

    /// Brings the window forward, on `page` if one is given.
    func show(page: SettingsPage? = nil) {
        if let page { navigation.selection = page }
        present(window)
    }

    /// The Clipboard popup's "Preferences…" (⌘,).
    func showClipboardHistory() {
        show(page: .clipboardHistory)
    }
}

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
    private let navigation = SettingsNavigation()

    private lazy var window: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mooring Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView(engine: engine, windows: windows, navigation: navigation))
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 640, height: 420))
        window.center()
        return window
    }()

    private init() {}

    /// Brings the window forward, on `page` if one is given.
    func show(page: SettingsPage? = nil) {
        if let page { navigation.selection = page }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

import AppKit
import SwiftUI

/// Explains why Windows needs Accessibility, while the controller polls for it.
struct AccessibilitySheet: View {
    let openSettingsPane: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mooring moves and resizes other apps' windows. macOS calls this Accessibility.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Open Privacy & Security", action: openSettingsPane)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// Shows the sheet in its own small window (Mooring has no main window to attach a sheet to).
/// It has no close button, so it goes away only through Cancel, trust arriving or the timeout.
@MainActor
final class AccessibilitySheetWindow: AccessibilitySheetPresenting {
    private weak var controller: WindowsController?
    private var window: NSWindow?

    init(controller: WindowsController) {
        self.controller = controller
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let sheet = AccessibilitySheet(
            openSettingsPane: { [weak controller] in controller?.openSettingsPane() },
            cancel: { [weak controller] in controller?.cancelTurnOn() }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: sheet))
        window.styleMask = [.titled]
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .floating
        return window
    }
}

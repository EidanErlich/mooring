// Adapted from Maccy@c376789: Maccy/FloatingPanel.swift
import AppKit
import SwiftUI

// An NSPanel subclass that implements floating panel traits.
// https://stackoverflow.com/questions/46023769/how-to-show-a-window-without-stealing-focus-on-macos
//
// Mooring's dropdown: a non-activating panel anchored under the status item.
// Maccy's AppState, Popup, PopupPosition, preview/slideout, saved size and
// position, resizing and dragging are removed; sizing follows the SwiftUI
// content, and Esc closes it.
final class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
    private(set) var isPresented = false
    private weak var statusBarButton: NSStatusBarButton?
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void, content: () -> Content) {
        self.onClose = onClose
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PanelPlacement.width, height: 200),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        delegate = self
        animationBehavior = .none
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let hosting = NSHostingController(rootView: content())
        hosting.sizingOptions = [.preferredContentSize]
        contentViewController = hosting
    }

    /// Shows the panel under `button`, on the button's screen.
    func open(below button: NSStatusBarButton) {
        statusBarButton = button
        contentViewController?.view.layoutSubtreeIfNeeded()
        reposition()
        orderFrontRegardless()
        makeKey()
        isPresented = true
        // Deferred, as upstream does: the button's own click tracking would undo it.
        DispatchQueue.main.async { button.isHighlighted = true }
    }

    /// Keeps the top edge under the icon when the content changes height.
    func windowDidResize(_ notification: Notification) {
        reposition()
    }

    private func reposition() {
        guard let button = statusBarButton, let buttonWindow = button.window,
              let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        setFrameOrigin(PanelPlacement.origin(below: buttonFrame, panelSize: frame.size, in: visibleFrame))
    }

    // Close automatically when out of focus, e.g. outside click.
    override func resignKey() {
        super.resignKey()
        close()
    }

    // Esc
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func close() {
        super.close()
        isPresented = false
        statusBarButton?.isHighlighted = false
        onClose()
    }

    // Allow text inputs inside the panel can receive focus
    override var canBecomeKey: Bool {
        true
    }
}

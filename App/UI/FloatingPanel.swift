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
//
// With an auto-hidden menu bar (or a full-screen Space), the status item's window
// stops being visible when the bar hides; its frame doesn't change, so occlusion is
// the signal. See PanelPlacement.response for what the panel does then.
final class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
    private(set) var isPresented = false
    private weak var statusBarButton: NSStatusBarButton?
    private let onClose: @MainActor () -> Void
    private var menuBarShown = true
    private var occlusionObserver: NSObjectProtocol?

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
        setMenuBarShown(button.window?.occlusionState.contains(.visible) ?? true)
        observeMenuBar(button.window)
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
              let screen = buttonWindow.screen ?? NSScreen.main
        else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let anchor = PanelPlacement.anchor(buttonFrame: buttonFrame, screenFrame: screen.frame, menuBarShown: menuBarShown)
        setFrameOrigin(PanelPlacement.origin(below: anchor, panelSize: frame.size, in: screen.visibleFrame))
    }

    private func observeMenuBar(_ buttonWindow: NSWindow?) {
        stopObservingMenuBar()
        guard let buttonWindow else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: buttonWindow, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuBarVisibilityChanged() }
        }
    }

    private func stopObservingMenuBar() {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
    }

    private func menuBarVisibilityChanged() {
        guard isPresented, let shown = statusBarButton?.window?.occlusionState.contains(.visible),
              shown != menuBarShown else { return }
        switch PanelPlacement.response(menuBarShown: shown, pointerInPanel: frame.contains(NSEvent.mouseLocation)) {
        case .close:
            close()
        case .moveFlush, .moveUnderBar:
            setMenuBarShown(shown)
            reposition()
        }
    }

    /// While flush with the top, the panel sits just below the menu bar's level, so the
    /// returning bar draws over it and the panel can't hide the status item's window.
    private func setMenuBarShown(_ shown: Bool) {
        menuBarShown = shown
        level = shown ? .statusBar : NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
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
        stopObservingMenuBar()
        isPresented = false
        statusBarButton?.isHighlighted = false
        onClose()
    }

    // Allow text inputs inside the panel can receive focus
    override var canBecomeKey: Bool {
        true
    }
}

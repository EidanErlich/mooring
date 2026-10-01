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
// the signal. See PanelPlacement.response for what the panel does then. That signal
// arrives only after the bar has slid away, so with auto-hide on the panel also
// watches the pointer and acts as it leaves the bar (PanelPlacement.predictedChange).
final class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
    private(set) var isPresented = false
    private weak var statusBarButton: NSStatusBarButton?
    private let onClose: @MainActor () -> Void
    private var menuBarShown = true
    private var occlusionObserver: NSObjectProtocol?
    private var pointerMonitors: [Any] = []
    /// How long a predicted hide waits for macOS to confirm it before moving back.
    private static var hideConfirmation: TimeInterval { 1 }

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
        watchPointer()
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
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors = []
    }

    /// "Automatically hide and show the menu bar" set to Always (or On desktop only).
    private var menuBarAutoHides: Bool {
        UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
    }

    private func watchPointer() {
        guard menuBarAutoHides else { return }
        acceptsMouseMovedEvents = true
        let moved: @MainActor () -> Void = { [weak self] in self?.pointerMoved() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { _ in
            MainActor.assumeIsolated { moved() }
        }) { pointerMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            MainActor.assumeIsolated { moved() }
            return event
        }) { pointerMonitors.append(local) }
    }

    private func pointerMoved() {
        guard isPresented, let buttonWindow = statusBarButton?.window,
              let change = PanelPlacement.predictedChange(
                  pointer: NSEvent.mouseLocation, barBottom: buttonWindow.frame.minY, panelFrame: frame,
                  menuBarShown: menuBarShown, autoHides: true)
        else { return }
        apply(change, menuBarShown: false)
        guard change == .moveFlush else { return }
        // If the bar stayed (the pointer went back up in time), move back under it.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideConfirmation) { [weak self] in
            guard let self, isPresented, !menuBarShown,
                  statusBarButton?.window?.occlusionState.contains(.visible) == true else { return }
            apply(.moveUnderBar, menuBarShown: true)
        }
    }

    private func menuBarVisibilityChanged() {
        guard isPresented, let shown = statusBarButton?.window?.occlusionState.contains(.visible),
              shown != menuBarShown else { return }
        apply(PanelPlacement.response(menuBarShown: shown, pointerInPanel: frame.contains(NSEvent.mouseLocation)),
              menuBarShown: shown)
    }

    private func apply(_ change: PanelPlacement.MenuBarChange, menuBarShown shown: Bool) {
        switch change {
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

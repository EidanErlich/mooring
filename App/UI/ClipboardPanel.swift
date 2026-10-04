// Adapted from Maccy@c376789: Maccy/FloatingPanel.swift
import AppKit
import ClipKit
import SwiftUI

// An NSPanel subclass that implements floating panel traits.
// https://stackoverflow.com/questions/46023769/how-to-show-a-window-without-stealing-focus-on-macos
//
// Mooring: the Clipboard popup (⇧⌘C, or Search… in the dropdown). ClipKit builds it on each start
// through `makePopupPanel` and drops it on stop, so its content (`popupView()`) is only ever built
// while Clipboard is on. Maccy's state (the saved size and position, the preview slideout, the
// popup's reset on close) is reached through `ClipKitPopup`; the rest is Maccy's window behaviour.
final class ClipboardPanel: NSPanel, NSWindowDelegate {
    private(set) var isPresented = false
    private weak var statusBarButton: NSStatusBarButton?

    override var isMovable: Bool {
        get { ClipKit.settingsValues().popupPosition != .statusItem }
        set {}
    }

    init(kit: ClipKit, statusBarButton: NSStatusBarButton?) {
        self.statusBarButton = statusBarButton
        super.init(
            contentRect: NSRect(origin: .zero, size: ClipKitPopup.savedSize),
            styleMask: [.nonactivatingPanel, .resizable, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Maccy's views watch for their own window becoming key by this identifier.
        identifier = NSUserInterfaceItemIdentifier(Bundle.main.bundleIdentifier ?? "dev.mooring.app")
        delegate = self

        animationBehavior = .none
        isFloatingPanel = true
        // Chrome autofill uses window layer 999; screenSaver (1000) sits just above it
        // while still covering status items / Spotlight. See #1403.
        level = .screenSaver
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        titlebarSeparatorStyle = .none
        isReleasedWhenClosed = false

        // Hide all traffic light buttons
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        contentView = NSHostingView(
            rootView: kit.popupView()
                // The safe area is ignored because the title bar still interferes with the geometry
                .ignoresSafeArea()
                .gesture(DragGesture().onEnded { [weak self] _ in
                    guard let self else { return }
                    ClipKitPopup.savePosition(of: self)
                })
        )
        contentView?.layer?.cornerRadius = ClipKitPopup.cornerRadius
    }

    func open(height: CGFloat, at position: ClipSettings.PopupPosition) {
        setContentSize(ClipKitPopup.openingSize(height: height, currentWidth: frame.width))
        setFrameOrigin(ClipKitPopup.origin(size: frame.size, at: position, statusBarButton: statusBarButton))
        orderFrontRegardless()
        makeKey()
        isPresented = true

        if position == .statusItem {
            DispatchQueue.main.async {
                self.statusBarButton?.isHighlighted = true
            }
        }
    }

    func verticallyResize(to newHeight: CGFloat) {
        var newSize = frame.size
        newSize.height = newHeight
        var newOrigin = frame.origin
        newOrigin.y += (frame.height - newSize.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        ClipKitPopup.panel(self, willResizeTo: frameSize)
    }

    func windowWillMove(_ notification: Notification) {
        ClipKitPopup.panelDidMove(self)
    }

    func windowDidMove(_ notification: Notification) {
        ClipKitPopup.panelDidMove(self)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        ClipKitPopup.panelWillStartLiveResize()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        ClipKitPopup.panelDidEndLiveResize()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        ClipKitPopup.panelDidBecomeKey()
    }

    func windowDidResignKey(_ notification: Notification) {
        ClipKitPopup.panelDidResignKey()
    }

    // Close automatically when out of focus, e.g. outside click.
    override func resignKey() {
        super.resignKey()
        // Don't hide if confirmation is shown.
        if !NSApp.windows.contains(where: { $0.className == "_NSAlertPanel" }) {
            close()
        }
    }

    override func close() {
        super.close()
        isPresented = false
        statusBarButton?.isHighlighted = false
        ClipKitPopup.panelDidClose()
    }

    // Allow text inputs inside the panel can receive focus
    override var canBecomeKey: Bool {
        true
    }
}

extension ClipboardPanel: @preconcurrency PopupPanel {}

// Adapted from Maccy@c376789: Maccy/FloatingPanel.swift
import AppKit
import Defaults

/// The Maccy state behind the popup window: its saved size and position, where it opens, and the
/// preview slideout's reactions to the window moving, resizing and gaining or losing focus. The
/// host's `PopupPanel` (Maccy's `FloatingPanel`, adapted in the app) forwards to these.
///
/// None of them creates Maccy's state: before ClipKit first starts they only read settings, or do
/// nothing.
@MainActor
public enum ClipKitPopup {
    /// The size the popup was last left at.
    public static var savedSize: NSSize { Defaults[.windowSize] }

    /// The corner radius Maccy gives the popup's content.
    public static var cornerRadius: CGFloat { Popup.cornerRadius + Popup.horizontalPadding }

    /// The content size for opening `height` tall: no wider than the saved size, and between the
    /// popup's minimum height and the saved height.
    public static func openingSize(height: CGFloat, currentWidth: CGFloat) -> NSSize {
        let size = Defaults[.windowSize]
        let minimumHeight = state?.popup.minimumHeight ?? 0
        return NSSize(width: min(currentWidth, size.width), height: max(min(height, size.height), minimumHeight))
    }

    /// Where a popup of `size` opens for `position`; the pointer when there's nothing better.
    public static func origin(size: NSSize, at position: ClipSettings.PopupPosition,
                              statusBarButton: NSStatusBarButton?) -> NSPoint {
        let position = PopupPosition(rawValue: position.rawValue) ?? .cursor
        return position.origin(size: size, statusBarButton: statusBarButton)
    }

    /// Call after the panel closed.
    public static func panelDidClose() {
        guard let state else { return }
        state.preview.state = .closed
        state.popup.reset()
    }

    public static func panelDidMove(_ panel: NSWindow) {
        guard let preview = state?.preview, !preview.state.isOpen else { return }
        let newSize = preview.computeSizeWithPreview(panel.frame.size, state: .open)
        preview.placement = preview.computePlacement(window: panel, for: newSize)
    }

    public static func savePosition(of panel: NSWindow) {
        guard let state, let screenFrame = panel.screen?.visibleFrame else { return }
        // Only store the size of the window without the preview
        let width = state.preview.contentWidth
        let frame = panel.frame
        let anchorX = frame.minX + width / 2 - screenFrame.minX
        let anchorY = frame.maxY - screenFrame.minY
        Defaults[.windowPosition] = NSPoint(x: anchorX / screenFrame.width, y: anchorY / screenFrame.height)
    }

    /// The size `panel` may take when the user resizes it to `frameSize`; also saves it.
    public static func panel(_ panel: NSWindow, willResizeTo frameSize: NSSize) -> NSSize {
        guard let state else { return frameSize }
        let preview = state.preview

        if panel.inLiveResize && preview.resizingMode == .none {
            let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
            let location: SlideoutPlacement = windowPoint.x <= panel.frame.width / 2 ? .left : .right
            if location == preview.placement && preview.state == .open {
                preview.startResize(mode: .slideout)
            } else {
                preview.startResize(mode: .content)
            }
        }

        var finalFrameSize = frameSize
        var minContent = preview.minimumContentWidth
        var minPreview = 0.0

        if panel.inLiveResize && preview.resizingMode != .none {
            if preview.resizingMode == .content && preview.state == .open {
                minPreview = preview.slideoutWidth
            }
            if preview.resizingMode == .slideout {
                minPreview = preview.minimumSlideoutWidth
                minContent = preview.contentWidth
            }
        }
        finalFrameSize.width = max(finalFrameSize.width, minContent + minPreview)

        if !preview.state.isAnimating {
            var size = panel.frame.size
            // Only store the size of the window without the preview
            size.width = preview.contentWidth
            Defaults[.windowSize] = size
            savePosition(of: panel)
        }

        finalFrameSize.height = max(finalFrameSize.height, state.popup.minimumHeight)
        return finalFrameSize
    }

    public static func panelWillStartLiveResize() {
        state?.preview.cancelAutoOpen()
    }

    public static func panelDidEndLiveResize() {
        guard let preview = state?.preview else { return }
        preview.startAutoOpen()
        preview.endResize()
    }

    public static func panelDidBecomeKey() {
        guard let state else { return }
        state.preview.enableAutoOpen()
        if state.navigator.leadHistoryItem != nil {
            state.preview.startAutoOpen()
        }
    }

    public static func panelDidResignKey() {
        state?.preview.disableAutoOpen()
    }

    /// Maccy's state, once a ClipKit has started (it exists from then on); nil before.
    private static var state: AppState? {
        ClipKit.hasStarted ? AppState.shared : nil
    }
}

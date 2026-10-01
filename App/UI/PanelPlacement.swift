import AppKit

/// Where the dropdown opens: its left edge under the icon, directly below the
/// menu bar, kept inside the visible frame of the screen that holds the icon.
enum PanelPlacement {
    static let width: CGFloat = 320
    static let maxHeightFraction: CGFloat = 0.7

    static func origin(below buttonFrame: NSRect, panelSize: NSSize, in visibleFrame: NSRect) -> NSPoint {
        let left = min(max(buttonFrame.minX, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
        let bottom = max(buttonFrame.minY - panelSize.height, visibleFrame.minY)
        return NSPoint(x: left, y: bottom)
    }

    static func maxHeight(in visibleFrame: NSRect) -> CGFloat {
        visibleFrame.height * maxHeightFraction
    }

    // MARK: - Auto-hidden menu bar

    /// What the open panel does when an auto-hidden menu bar hides or comes back.
    enum MenuBarChange: Equatable {
        case close, moveFlush, moveUnderBar
    }

    /// The rect the panel hangs from: the icon while the bar shows, otherwise the top
    /// edge of the screen, so no gap is left where the bar was.
    static func anchor(buttonFrame: NSRect, screenFrame: NSRect, menuBarShown: Bool) -> NSRect {
        guard !menuBarShown else { return buttonFrame }
        return NSRect(x: buttonFrame.minX, y: screenFrame.maxY, width: buttonFrame.width, height: 0)
    }

    /// The bar hiding closes the panel unless the pointer is in it; then the panel
    /// moves up flush with the screen top until the bar comes back.
    static func response(menuBarShown: Bool, pointerInPanel: Bool) -> MenuBarChange {
        if menuBarShown { return .moveUnderBar }
        return pointerInPanel ? .moveFlush : .close
    }

    /// macOS reports the bar hidden only after it has slid away, so with auto-hide on
    /// the panel acts as soon as the pointer leaves the bar's strip, together with
    /// the bar. Nil means wait for macOS.
    static func predictedChange(pointer: NSPoint, barBottom: CGFloat, panelFrame: NSRect,
                                menuBarShown: Bool, autoHides: Bool) -> MenuBarChange? {
        guard autoHides, menuBarShown, pointer.y < barBottom else { return nil }
        return response(menuBarShown: false, pointerInPanel: panelFrame.contains(pointer))
    }
}

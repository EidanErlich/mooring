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
}

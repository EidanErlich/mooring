import AppKit

/// What Maccy's views ask of the popup window. Maccy reached its `FloatingPanel` through
/// `AppDelegate`, which isn't taken; the host app sets `AppState.panel` instead.
protocol PopupPanel: NSWindow {
    var isPresented: Bool { get }
    func open(height: CGFloat, at popupPosition: PopupPosition)
    func verticallyResize(to newHeight: CGFloat)
}

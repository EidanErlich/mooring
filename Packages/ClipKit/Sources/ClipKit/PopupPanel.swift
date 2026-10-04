import AppKit

/// The popup window, which the host app supplies (`ClipKit.makePopupPanel`). Maccy reached its
/// `FloatingPanel` through `AppDelegate`, which isn't taken; Maccy's views and `Popup` reach this
/// through `AppState.panel` instead. Maccy's `Popup` isn't main-actor isolated, so neither is this;
/// a Swift 6 host conforms with `@preconcurrency`.
public protocol PopupPanel: NSWindow {
    var isPresented: Bool { get }
    /// Shows the panel `height` tall (within the saved size), placed as `position` says.
    func open(height: CGFloat, at position: ClipSettings.PopupPosition)
    func verticallyResize(to newHeight: CGFloat)
}

extension PopupPanel {
    /// Maccy's call sites pass its own `PopupPosition`.
    func open(height: CGFloat, at position: PopupPosition) {
        open(height: height, at: ClipSettings.PopupPosition(rawValue: position.rawValue) ?? .cursor)
    }
}

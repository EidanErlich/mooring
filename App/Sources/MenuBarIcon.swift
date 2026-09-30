import AppKit

/// The menu-bar anchor: outline when Mooring is off, filled when it's on.
/// Badges (lid, battery, attention) arrive in stage 1b.
enum MenuBarIcon {
    static let outlineAssetName = "MenubarAnchor"
    static let filledAssetName = "MenubarAnchorFill"

    static func image(filled: Bool) -> NSImage {
        let name = filled ? filledAssetName : outlineAssetName
        guard let image = NSImage(named: name) else {
            preconditionFailure("Missing asset \(name) in Assets.xcassets")
        }
        return image
    }
}

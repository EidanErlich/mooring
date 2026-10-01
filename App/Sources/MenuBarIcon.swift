import AppKit

/// The menu-bar anchor: outline when Mooring is off, filled when it's on, with
/// a lid or battery badge at the bottom right and an attention dot at the top right.
enum MenuBarIcon {
    static let outlineAssetName = "MenubarAnchor"
    static let filledAssetName = "MenubarAnchorFill"
    static let size = NSSize(width: 18, height: 18)

    static func image(for icon: IconState) -> NSImage {
        let anchor = asset(filled: icon.filled)
        guard icon.badge != .none || icon.attention else { return anchor }
        let image = NSImage(size: size, flipped: false) { rect in
            anchor.draw(in: rect)
            if let symbol = badgeSymbol(icon.badge) {
                knockOut(NSRect(x: 8, y: 0, width: 10, height: 9))
                let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)?
                    .draw(in: NSRect(x: 9, y: 0.5, width: 9, height: 8))
            }
            if icon.attention {
                knockOut(NSRect(x: 12, y: 12, width: 6, height: 6))
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12.5, y: 12.5, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func asset(filled: Bool) -> NSImage {
        let name = filled ? filledAssetName : outlineAssetName
        guard let image = NSImage(named: name) else {
            preconditionFailure("Missing asset \(name) in Assets.xcassets")
        }
        return image
    }

    private static func badgeSymbol(_ badge: IconBadge) -> String? {
        switch badge {
        case .none: nil
        case .lid: "laptopcomputer"
        case .lidOnBattery: "battery.25"
        }
    }

    /// Clears the anchor behind a badge so the badge reads at 18 pt.
    private static func knockOut(_ rect: NSRect) {
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}

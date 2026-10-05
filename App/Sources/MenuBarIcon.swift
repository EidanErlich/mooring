import AppKit

/// Draws the menu-bar icon (docs/design/2026-10-01-menu-bar-icon-design.md):
/// a dimmed anchor when off, a solid pill when awake (anchor, optional LID tag and one
/// kind label, all cut out so macOS tints it as a template), and an orange "!" pill
/// when something needs attention. Decisions about *what* to show live in MenuBarState.
enum MenuBarIcon {
    static let height: CGFloat = 18
    static let outlineAssetName = "MenubarAnchor"
    static let filledAssetName = "MenubarAnchorFill"

    private static let cornerRadius: CGFloat = 5
    private static let leading: CGFloat = 4, trailing: CGFloat = 5, gap: CGFloat = 3
    private static let anchorSize: CGFloat = 13
    private static var labelFont: NSFont { .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold) }
    private static var lidFont: NSFont { .systemFont(ofSize: 9.5, weight: .heavy) }
    private static let lidTagHeight: CGFloat = 12

    private enum Element {
        case lidTag
        case text(String)
        case symbol(String)
    }

    static func image(for state: MenuBarState) -> NSImage {
        switch state {
        case .off: offImage()
        case .awake(let lid, let kind): pillImage(elements(lid: lid, kind: kind))
        case .attention: attentionImage()
        }
    }

    private static func elements(lid: Bool, kind: AwakeKind) -> [Element] {
        var elements: [Element] = lid ? [.lidTag] : []
        switch kind {
        case .indefinite: elements.append(.symbol("infinity"))
        case .task: elements.append(.symbol("play.fill"))
        case .timed(let seconds?): elements.append(.text(MenuBarText.timeLabel(seconds)))
        case .timed(nil): break
        }
        return elements
    }

    // MARK: - States

    private static func offImage() -> NSImage {
        let anchor = asset(outlineAssetName)
        let image = NSImage(size: NSSize(width: height, height: height), flipped: false) { rect in
            anchor.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.55)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func pillImage(_ elements: [Element]) -> NSImage {
        let anchor = asset(filledAssetName)
        let widths = elements.map(width(of:))
        let total = (leading + anchorSize + widths.reduce(0) { $0 + gap + $1 } + trailing).rounded(.up)
        let image = NSImage(size: NSSize(width: total, height: height), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            let anchorY = (height - anchorSize) / 2
            cutOut(anchor, in: NSRect(x: leading, y: anchorY, width: anchorSize, height: anchorSize))
            var left = leading + anchorSize
            for (element, elementWidth) in zip(elements, widths) {
                left += gap
                draw(element, at: left, width: elementWidth)
                left += elementWidth
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func attentionImage() -> NSImage {
        // Heavy and larger: white on orange needs the extra weight to read at menu-bar size.
        let mark = symbol("exclamationmark", pointSize: 12, weight: .black)
        let image = NSImage(size: NSSize(width: 24, height: height), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            let markRect = NSRect(x: (rect.width - mark.size.width) / 2, y: (height - mark.size.height) / 2,
                                  width: mark.size.width, height: mark.size.height)
            tinted(mark, .white).draw(in: markRect)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Elements

    private static func width(of element: Element) -> CGFloat {
        switch element {
        case .lidTag: textSize("LID", lidFont).width + 6
        case .text(let string): textSize(string, labelFont).width
        case .symbol(let name): symbol(name).size.width
        }
    }

    /// Draws one element inside the pill; everything is cut out except the LID letters.
    private static func draw(_ element: Element, at left: CGFloat, width: CGFloat) {
        switch element {
        case .text(let string):
            let size = textSize(string, labelFont)
            cutOut(textImage(string, labelFont), in: NSRect(x: left, y: (height - size.height) / 2,
                                                             width: size.width, height: size.height))
        case .symbol(let name):
            let image = symbol(name)
            cutOut(image, in: NSRect(x: left, y: (height - image.size.height) / 2,
                                     width: image.size.width, height: image.size.height))
        case .lidTag:
            // An inverted tag: a capsule hole in the pill, with the letters left opaque.
            let tag = NSRect(x: left, y: (height - lidTagHeight) / 2, width: width, height: lidTagHeight)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(roundedRect: tag, xRadius: 3, yRadius: 3).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let size = textSize("LID", lidFont)
            textImage("LID", lidFont).draw(in: NSRect(x: tag.midX - size.width / 2, y: tag.midY - size.height / 2,
                                                      width: size.width, height: size.height))
        }
    }

    // MARK: - Drawing helpers

    private static func cutOut(_ image: NSImage, in rect: NSRect) {
        image.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
    }

    private static func textSize(_ string: String, _ font: NSFont) -> NSSize {
        let size = NSAttributedString(string: string, attributes: [.font: font]).size()
        return NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    private static func textImage(_ string: String, _ font: NSFont) -> NSImage {
        let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.black])
        return NSImage(size: textSize(string, font), flipped: false) { _ in
            text.draw(at: .zero)
            return true
        }
    }

    private static func symbol(_ name: String, pointSize: CGFloat = 10, weight: NSFont.Weight = .bold) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            preconditionFailure("Missing SF Symbol \(name)")
        }
        return image
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func asset(_ name: String) -> NSImage {
        guard let image = NSImage(named: name) else {
            preconditionFailure("Missing asset \(name) in Assets.xcassets")
        }
        return image
    }
}

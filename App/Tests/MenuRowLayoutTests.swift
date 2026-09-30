import AppKit
import SwiftUI
import Testing
@testable import Mooring

@MainActor
struct MenuRowLayoutTests {
    /// "While an app runs…" rows: the app icon must sit before the name, never on top of it.
    @Test func iconSitsBeforeTheTitle() throws {
        // An outline, not a filled square: text overlapped by the icon stays visible to the scan.
        let icon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.red.setStroke()
            let frame = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            frame.lineWidth = 1
            frame.stroke()
            return true
        }
        let row = MenuRow(title: "WWWW", icon: icon) {}
            .frame(width: 200)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: row)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)

        var redColumns: [Int] = []
        var textColumns: [Int] = []
        for column in 0..<bitmap.pixelsWide {
            for line in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: column, y: line)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { continue }
                if color.redComponent > 0.8 && color.greenComponent < 0.3 && color.blueComponent < 0.3 {
                    redColumns.append(column)
                } else if color.redComponent < 0.4 && color.greenComponent < 0.4 && color.blueComponent < 0.4 {
                    textColumns.append(column)
                }
            }
        }
        let iconEnd = try #require(redColumns.max())
        let textStart = try #require(textColumns.min())
        #expect(iconEnd < textStart)
    }
}

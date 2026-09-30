import AppKit
import Testing
@testable import Mooring

struct MenuBarIconTests {
    /// Template images are what let macOS tint the icon for light and dark menu bars.
    @Test(arguments: [false, true])
    func anchorIsAn18ptTemplateImage(filled: Bool) {
        let image = MenuBarIcon.image(filled: filled)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
    }
}

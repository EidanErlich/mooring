import AppKit
import Testing
@testable import Mooring

struct MenuBarIconTests {
    /// Template images are what let macOS tint the icon for light and dark menu bars.
    @Test(arguments: [false, true])
    func anchorIsAn18ptTemplateImage(filled: Bool) {
        for badge in [IconBadge.none, .lid, .lidOnBattery] {
            for attention in [false, true] {
                let image = MenuBarIcon.image(for: IconState(filled: filled, badge: badge, attention: attention))
                #expect(image.isTemplate)
                #expect(image.size == NSSize(width: 18, height: 18))
            }
        }
    }
}

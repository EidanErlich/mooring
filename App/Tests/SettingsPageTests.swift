import AwakeKit
import Testing
@testable import Mooring

struct SettingsPageTests {
    @Test func pagesAndGroupsMatchSpec() {
        #expect(SettingsPage.allCases.map(\.title) == ["General", "Keep Awake", "Lid & Battery", "Advanced"])
        #expect(SettingsPage.allCases.map(\.group) == ["General", "Awake", "Awake", "Mooring"])
    }

    @Test func clickLevelOptionsRoundTrip() {
        #expect(ClickLevelOption.allCases.map(\.title)
            == ["Keep the Mac awake", "Keep the Mac and screen awake", "Keep the Mac awake with the lid closed"])
        #expect(ClickLevelOption(level: .screenOn) == .screenOn)
        #expect(ClickLevelOption(level: .system) == .system)
        #expect(ClickLevelOption(level: AwakeLevel(display: false, lid: true)) == .lidClosed)
        #expect(ClickLevelOption(level: AwakeLevel(display: true, lid: true)) == .lidClosed)
        #expect(ClickLevelOption.lidClosed.level == AwakeLevel(display: false, lid: true))
    }
}

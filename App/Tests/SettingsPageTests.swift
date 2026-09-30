import AwakeKit
import Testing
@testable import Mooring

struct SettingsPageTests {
    @Test func pagesAndGroupsMatchSpec() {
        #expect(SettingsPage.allCases.map(\.title) == ["General", "Keep Awake"])
        #expect(SettingsPage.allCases.map(\.group) == ["General", "Awake"])
    }

    @Test func clickLevelOptionsRoundTrip() {
        #expect(ClickLevelOption.allCases.map(\.title) == ["Keep the Mac awake", "Keep the Mac and screen awake"])
        #expect(ClickLevelOption(level: .screenOn) == .screenOn)
        #expect(ClickLevelOption(level: .system) == .system)
    }
}

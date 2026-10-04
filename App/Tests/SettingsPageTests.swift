import AwakeKit
import Testing
import WindowKit
@testable import Mooring

@MainActor
struct SettingsPageTests {
    private let windowsPages: [SettingsPage] = [
        .windowsBehavior, .windowsKeybinds, .windowsGestures, .windowsRadialMenu, .windowsPreview, .windowsExcludedApps
    ]

    @Test func pagesAndGroupsMatchSpec() {
        #expect(SettingsPage.allCases.map(\.title) == [
            "General", "Keep Awake", "Lid & Battery", "Agents",
            "Behavior", "Keybinds", "Gestures", "Radial Menu", "Preview", "Excluded Apps", "Advanced"
        ])
        #expect(SettingsPage.allCases.map(\.group) == [
            "General", "Awake", "Awake", "Awake",
            "Windows", "Windows", "Windows", "Windows", "Windows", "Windows", "Mooring"
        ])
    }

    @Test func windowsGroupListsSixPagesInOrder() {
        #expect(SettingsPage.allCases.filter { $0.group == "Windows" } == windowsPages)
        #expect(windowsPages.map(\.title) == ["Behavior", "Keybinds", "Gestures", "Radial Menu", "Preview", "Excluded Apps"])
        #expect(windowsPages.compactMap(\.windowSettingsPage) == WindowSettingsPage.allCases)
        #expect(SettingsPage.allCases.filter { $0.windowSettingsPage != nil } == windowsPages)
    }

    /// Off means off: until Windows is on, a page is the banner alone and Loop's page is never built.
    @Test func windowsPagesShowOffBannerWhenOff() {
        for page in windowsPages {
            for state in [WindowsController.State.off, .waitingForTrust, .needsAccessibility] {
                #expect(page.windowsContent(for: state) == .offBanner)
            }
            #expect(page.windowsContent(for: .on) == page.windowSettingsPage.map(WindowsPageContent.loopPage))
        }
        #expect(SettingsPage.windowsBehavior.windowsContent(for: .on) == .loopPage(.behavior))
        #expect(SettingsPage.general.windowsContent(for: .on) == nil)
        #expect(WindowsPageBanner.title == "Windows is off")
        #expect(WindowsPageBanner.turnOnTitle == "Turn On…")
    }

    @Test func behaviorPageHasWindowManagerToggle() {
        #expect(windowsPages.filter(\.hasWindowManagerToggle) == [.windowsBehavior])
        #expect(WindowManagerToggle.title == "Window Manager")
    }

    @Test func windowManagerToggleTurnsWindowsOnAndOff() {
        let windows = WindowsController.fake(.off)
        let isOn = WindowManagerToggle.isOn(windows)
        #expect(!isOn.wrappedValue)
        isOn.wrappedValue = true
        #expect(windows.state == .on)
        #expect(isOn.wrappedValue)
        isOn.wrappedValue = false
        #expect(windows.state == .off)
    }

    @Test func agentsPageUsesSparkles() {
        #expect(SettingsPage.agents.systemImage == "sparkles")
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

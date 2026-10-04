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
            "General", "Shortcuts", "Keep Awake", "Lid & Battery", "Agents",
            "Behavior", "Keybinds", "Gestures", "Radial Menu", "Preview", "Excluded Apps", "Advanced"
        ])
        #expect(SettingsPage.allCases.map(\.group) == [
            "General", "General", "Awake", "Awake", "Awake",
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

    /// Without MultitouchSupport the Gestures page is a banner while Windows is on; the other pages are unaffected.
    @Test func gesturesPageShowsUnavailableBannerWithoutMultitouch() {
        #expect(WindowsPageBanner.gesturesUnavailableTitle == "Gestures aren't available on this Mac")
        #expect(SettingsPage.windowsGestures.windowsContent(for: .on, gesturesAvailable: false)
            == .unavailableBanner(WindowsPageBanner.gesturesUnavailableTitle))
        #expect(SettingsPage.windowsGestures.windowsContent(for: .on, gesturesAvailable: true) == .loopPage(.gestures))
        #expect(SettingsPage.windowsGestures.windowsContent(for: .off, gesturesAvailable: false) == .offBanner)
        for page in windowsPages where page != .windowsGestures {
            #expect(page.windowsContent(for: .on, gesturesAvailable: false) == page.windowSettingsPage.map(WindowsPageContent.loopPage))
        }
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

    /// The switch shows whether Windows is wanted, so it can turn Windows off while it waits for Accessibility.
    @Test func windowManagerToggleReflectsWanted() {
        for state in [WindowsController.State.waitingForTrust, .needsAccessibility] {
            let windows = WindowsController.fake(state)
            let isOn = WindowManagerToggle.isOn(windows)
            #expect(isOn.wrappedValue, "\(state)")
            isOn.wrappedValue = false
            #expect(windows.state == .off, "\(state)")
            #expect(!isOn.wrappedValue, "\(state)")
        }
        #expect(WindowManagerToggle.isOn(.fake(.on)).wrappedValue)
        #expect(!WindowManagerToggle.isOn(.fake(.off)).wrappedValue)
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

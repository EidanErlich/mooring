import Testing
@testable import Mooring

struct AppSessionTextTests {
    /// Coming back to the dropdown, the row says which apps keep the Mac awake.
    @Test func rowTitleNamesThePickedApps() {
        #expect(AppSessionText.rowTitle(appNames: []) == "While an app runs…")
        #expect(AppSessionText.rowTitle(appNames: ["Xcode"]) == "While Xcode runs")
        #expect(AppSessionText.rowTitle(appNames: ["Xcode", "Safari"]) == "While Xcode and Safari run")
        #expect(AppSessionText.rowTitle(appNames: ["Xcode", "Safari", "Music"]) == "While 3 apps run")
    }
}

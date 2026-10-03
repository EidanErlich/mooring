import Foundation
import Testing
@testable import Mooring

struct TestHostTests {
    /// When Xcode launches the app only to host tests, it must not start the engine,
    /// which would read and write the user's real ~/Library/Application Support/Mooring.
    @Test func appKnowsItIsHostingTests() {
        #expect(AppDelegate.isHostingTests)
    }
}

struct InfoPlistTests {
    /// Approval requests stay on screen until answered: Alerts by default, not Banners that vanish in seconds.
    @Test func notificationsDefaultToAlerts() {
        let style = Bundle(for: AppDelegate.self).object(forInfoDictionaryKey: "NSUserNotificationAlertStyle")
        #expect(style as? String == "alert")
    }
}

import Defaults
import Foundation
import Testing
@testable import WindowKit

/// Clears the scratch suite tests write to. The real `dev.mooring.windows` is never opened under test.
func resetScratchWindowsSuite() {
    precondition(UserDefaults.windowKitSuiteName != UserDefaults.windowKitProductionSuiteName)
    UserDefaults.standard.removePersistentDomain(forName: UserDefaults.windowKitSuiteName)
}

extension WindowKitGlobalStateTests {
    @Suite
    @MainActor
    struct WindowsDefaultsTests {
        @Test func testsUseAScratchSuite() {
            #expect(UserDefaults.windowKitProductionSuiteName == "dev.mooring.windows")
            #expect(UserDefaults.windowKitSuiteName == "dev.mooring.windows.tests")
        }

        @Test func windowsDefaultsUseOwnSuite() throws {
            resetScratchWindowsSuite()
            defer { resetScratchWindowsSuite() }
            let suite = try #require(UserDefaults(suiteName: UserDefaults.windowKitSuiteName))
            let key = Defaults.Keys.timesLooped

            let marker = 424_242
            Defaults[key] = marker

            #expect(suite.integer(forKey: key.name) == marker)
            // Defaults registers default values in the process-wide registration domain, which every
            // `UserDefaults` reads, so check the keys the standard domain actually stores.
            #expect(UserDefaults.standard.integer(forKey: key.name) != marker)
            let stored = CFPreferencesCopyKeyList(
                kCFPreferencesCurrentApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? [String] ?? []
            #expect(!stored.contains(key.name))
            #expect(key.suite == UserDefaults.windowKit)
            #expect(Defaults.Keys.keybinds.suite == UserDefaults.windowKit)
            #expect(Defaults.Keys.triggerKey.suite == UserDefaults.windowKit)
            #expect(Defaults.Keys.hideMenuBarIcon.suite == UserDefaults.windowKit)
            #expect(Defaults.Keys.lastMigratorURL.suite == UserDefaults.windowKit)
        }
    }
}

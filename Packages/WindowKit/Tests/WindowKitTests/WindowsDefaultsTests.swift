import Defaults
import Foundation
import Testing
@testable import WindowKit

struct WindowsDefaultsTests {
    @Test func windowsDefaultsUseOwnSuite() throws {
        let suite = try #require(UserDefaults(suiteName: "dev.mooring.windows"))
        let key = Defaults.Keys.timesLooped
        // The stored value, not `object(forKey:)`, which also sees the registered default.
        let saved = UserDefaults.standard.persistentDomain(forName: "dev.mooring.windows")?[key.name]
        defer {
            if let saved {
                suite.set(saved, forKey: key.name)
            } else {
                suite.removeObject(forKey: key.name)
            }
        }

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

import AwakeKit
import Foundation
import Testing

struct SettingsTests {
    @Test func waitingTimeoutDefaultsTo30Minutes() {
        #expect(AwakeSettings().agentWaitingTimeout == 1800)
    }

    @Test func oldSettingsDecodeWithoutWaitingTimeout() throws {
        let old = #"{"clickDuration":3600,"agentKeepAwake":"explicit"}"#
        let decoded = try JSONDecoder().decode(AwakeSettings.self, from: Data(old.utf8))
        #expect(decoded.agentWaitingTimeout == 1800)
        #expect(decoded.agentKeepAwake == .explicit)
    }

    @Test func waitingTimeoutRoundTrips() throws {
        var settings = AwakeSettings()
        settings.agentWaitingTimeout = 3600
        let decoded = try JSONDecoder().decode(AwakeSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.agentWaitingTimeout == 3600)
        #expect(decoded == settings)
    }

    @Test func newLidKeysDefault() {
        let settings = AwakeSettings()
        #expect(settings.agentLidApproval == .askWhenOpenEnded)
        #expect(settings.agentSessionLid)
        #expect(settings.agentLidAlwaysAllowed.isEmpty)
    }

    @Test func olderSettingsDecodeWithLidDefaults() throws {
        let old = #"{"clickDuration":3600,"agentLid":"never"}"#
        let decoded = try JSONDecoder().decode(AwakeSettings.self, from: Data(old.utf8))
        #expect(decoded.agentLidApproval == .askWhenOpenEnded)
        #expect(decoded.agentSessionLid)
        #expect(decoded.agentLidAlwaysAllowed.isEmpty)
    }

    @Test func lidKeysRoundTrip() throws {
        var settings = AwakeSettings()
        settings.agentLidApproval = .alwaysAsk
        settings.agentSessionLid = false
        settings.agentLidAlwaysAllowed = ["Claude Code", "Codex"]
        let decoded = try JSONDecoder().decode(AwakeSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.agentLidApproval == .alwaysAsk)
        #expect(!decoded.agentSessionLid)
        #expect(decoded.agentLidAlwaysAllowed == ["Claude Code", "Codex"])
    }

    @Test func agentNotificationsDefaultsOn() {
        #expect(AwakeSettings().agentNotifications)
    }

    @Test func olderSettingsDecodeNotificationsOn() throws {
        let old = #"{"clickDuration":3600}"#
        let decoded = try JSONDecoder().decode(AwakeSettings.self, from: Data(old.utf8))
        #expect(decoded.agentNotifications)
    }
}

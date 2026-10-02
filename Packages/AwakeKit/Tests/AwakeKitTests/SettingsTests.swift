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
}

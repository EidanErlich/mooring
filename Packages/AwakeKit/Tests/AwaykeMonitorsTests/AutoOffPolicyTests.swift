import AwaykeMonitors
import Testing

// Ported from Awayke@b502251: Tests/main.swift. The five manual-override cases
// are gone because Mooring has no one-off override (docs/SPEC.md, Guardrail settings).
struct AutoOffPolicyTests {
    @Test func thresholdZeroDisables() {
        #expect(AutoOffPolicy.decide(intent: true, suspended: false, percent: 5, onAC: false, threshold: 0) == .none)
    }

    @Test func suspendsBelowThresholdOnBattery() {
        #expect(AutoOffPolicy.decide(intent: true, suspended: false, percent: 19, onAC: false, threshold: 20) == .suspend)
    }

    @Test func noSuspendAtExactlyThreshold() {
        #expect(AutoOffPolicy.decide(intent: true, suspended: false, percent: 20, onAC: false, threshold: 20) == .none)
    }

    @Test func neverSuspendsOnAC() {
        #expect(AutoOffPolicy.decide(intent: true, suspended: false, percent: 5, onAC: true, threshold: 20) == .none)
    }

    @Test func noSuspendWithoutIntent() {
        #expect(AutoOffPolicy.decide(intent: false, suspended: false, percent: 5, onAC: false, threshold: 20) == .none)
    }

    @Test func resumesAtThresholdPlusHysteresisOnAC() {
        #expect(AutoOffPolicy.decide(intent: true, suspended: true, percent: 25, onAC: true, threshold: 20) == .resume)
    }

    @Test func noResumeBelowHysteresis() {
        #expect(AutoOffPolicy.decide(intent: true, suspended: true, percent: 24, onAC: true, threshold: 20) == .none)
    }

    @Test func resumeRequiresAC() {
        #expect(AutoOffPolicy.decide(intent: true, suspended: true, percent: 30, onAC: false, threshold: 20) == .none)
    }
}

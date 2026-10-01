import AwakeKit
import Testing
@testable import Mooring

private let onAC = PowerSnapshot(onAC: true, batteryPercent: 80)
private let onBattery = PowerSnapshot(onAC: false, batteryPercent: 80)

private func state(system: Bool = true, lid: Bool = false, suspensions: Set<Suspension> = []) -> TargetState {
    TargetState(systemAssertion: system, displayAssertion: false, lidSleepDisabled: lid, suspensions: suspensions)
}

struct IconStateTests {
    @Test func offIsPlainOutline() {
        #expect(IconState.from(state: .off, wantsLid: false, helperEnabled: true, power: onAC)
            == IconState(filled: false, badge: .none, attention: false))
    }

    @Test func lidAppliedShowsLidBadge() {
        #expect(IconState.from(state: state(lid: true), wantsLid: true, helperEnabled: true, power: onAC).badge == .lid)
        #expect(IconState.from(state: state(lid: true), wantsLid: true, helperEnabled: true, power: onBattery).badge
            == .lidOnBattery)
    }

    @Test func wantingLidWithoutHelperNeedsAttention() {
        let icon = IconState.from(state: state(), wantsLid: true, helperEnabled: false, power: onAC)
        #expect(icon.attention)
        #expect(icon.badge == .none)
        #expect(icon.filled)
    }

    @Test func suspensionNeedsAttention() {
        #expect(IconState.from(state: state(suspensions: [.thermal]), wantsLid: true, helperEnabled: true, power: onAC)
            .attention)
    }
}

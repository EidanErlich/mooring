import AwakeKit
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_000_000)
private let ac = PowerSnapshot(onAC: true, batteryPercent: nil)

private func lease(_ id: String, _ level: AwakeLevel, expiresAt: Date? = nil) -> Lease {
    Lease(id: id, owner: .menu, reason: "r", level: level, expiresAt: expiresAt, createdAt: now)
}

private func run(_ leases: [Lease]) -> TargetState {
    target(leases: leases, power: ac, thermal: .nominal, lidClosed: nil, settings: AwakeSettings(), now: now)
}

struct TargetTests {
    @Test func noLeasesIsOff() {
        #expect(run([]) == .off)
    }

    @Test func anyLiveLeasePreventsSystemSleep() {
        let state = run([lease("a", .system)])
        #expect(state.systemAssertion)
        #expect(!state.displayAssertion)
    }

    @Test func displayIsTheUnionOverLiveLeases() {
        #expect(run([lease("a", .system), lease("b", .screenOn)]).displayAssertion)
    }

    @Test func expiredLeasesAreIgnored() {
        #expect(run([lease("a", .screenOn, expiresAt: now)]) == .off)
    }

    @Test func lidFlagIsCarriedButNoSuspensionsYet() {
        let state = run([lease("a", AwakeLevel(display: false, lid: true))])
        #expect(state.lidSleepDisabled)
        #expect(state.suspensions.isEmpty)
    }
}

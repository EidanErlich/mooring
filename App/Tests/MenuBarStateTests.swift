import AwakeKit
import Foundation
import Testing
@testable import Mooring

private let now = Date(timeIntervalSince1970: 1_000_000)
private let lidLevel = AwakeLevel(display: false, lid: true)

private func lease(_ id: String, left: TimeInterval? = nil, watched: Bool = false, level: AwakeLevel = .system) -> Lease {
    Lease(id: id, owner: .menu, reason: "r", level: level, expiresAt: left.map { now.addingTimeInterval($0) },
          watch: watched ? WatchedProcess(pid: 1, startTime: now) : nil, createdAt: now)
}

private func awake(lid: Bool = false, suspensions: Set<Suspension> = []) -> TargetState {
    TargetState(systemAssertion: true, displayAssertion: false, lidSleepDisabled: lid, suspensions: suspensions)
}

private func state(
    _ leases: [Lease], _ target: TargetState = awake(), wantsLid: Bool = false,
    helperEnabled: Bool = true, showTimeLeft: Bool = true
) -> MenuBarState {
    MenuBarState.from(leases: leases, state: target, wantsLid: wantsLid, helperEnabled: helperEnabled,
                      showTimeLeft: showTimeLeft, now: now)
}

struct MenuBarStateTests {
    @Test func offWhenNothingIsHeld() {
        #expect(state([], .off) == .off)
    }

    @Test func indefiniteTaskAndTimedKinds() {
        #expect(state([lease("a")]) == .awake(lid: false, kind: .indefinite))
        #expect(state([lease("a", watched: true)]) == .awake(lid: false, kind: .task))
        #expect(state([lease("a", left: 4320)]) == .awake(lid: false, kind: .timed(4320)))
    }

    @Test func kindFollowsTheLeaseThatEndsLast() {
        let timed = lease("t", left: 3600), task = lease("p", watched: true), forever = lease("f")
        #expect(state([timed, task]) == .awake(lid: false, kind: .task))
        #expect(state([timed, task, forever]) == .awake(lid: false, kind: .indefinite))
    }

    @Test func lidTagFollowsAppliedNotWanted() {
        let lid = lease("menu", level: lidLevel)
        #expect(state([lid], awake(lid: false), wantsLid: true) == .awake(lid: false, kind: .indefinite))
        #expect(state([lid], awake(lid: true), wantsLid: true) == .awake(lid: true, kind: .indefinite))
    }

    @Test func toggleHidesOnlyTimedLabels() {
        #expect(state([lease("a", left: 600)], showTimeLeft: false) == .awake(lid: false, kind: .timed(nil)))
        #expect(state([lease("a", watched: true)], showTimeLeft: false) == .awake(lid: false, kind: .task))
        #expect(state([lease("a")], showTimeLeft: false) == .awake(lid: false, kind: .indefinite))
    }

    @Test func attentionBeatsAwake() {
        #expect(state([lease("a")], awake(suspensions: [.thermal])) == .attention(.suspension(.thermal)))
        #expect(state([lease("a", level: lidLevel)], wantsLid: true, helperEnabled: false)
            == .attention(.helperNeedsApproval))
    }

    @Test func attentionReasonPriority() {
        #expect(state([lease("a")], awake(suspensions: [.lidNeedsAC, .thermal, .lowBatteryLid, .lowBatteryAll]))
            == .attention(.suspension(.lowBatteryAll)))
        #expect(state([lease("a")], awake(suspensions: [.lidNeedsAC, .thermal])) == .attention(.suspension(.thermal)))
    }
}

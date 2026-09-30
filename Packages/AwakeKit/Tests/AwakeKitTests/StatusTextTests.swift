import AwakeKit
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_000_000)

private func lease(
    _ id: String, _ level: AwakeLevel = .system, left: TimeInterval? = nil,
    watch: WatchedProcess? = nil, reason: String = "r"
) -> Lease {
    Lease(id: id, owner: .menu, reason: reason, level: level,
          expiresAt: left.map { now.addingTimeInterval($0) }, watch: watch, createdAt: now)
}

private func stateFor(_ leases: [Lease]) -> TargetState {
    target(leases: leases, power: PowerSnapshot(onAC: true, batteryPercent: nil), thermal: .nominal,
           lidClosed: nil, settings: AwakeSettings(), now: now)
}

struct StatusTextTests {
    @Test func remainingRoundsUpToTheMinute() {
        #expect(DurationText.remaining(30) == "1m")
        #expect(DurationText.remaining(60) == "1m")
        #expect(DurationText.remaining(61) == "2m")
        #expect(DurationText.remaining(3600) == "1h")
        #expect(DurationText.remaining(3601) == "1h 1m")
        #expect(DurationText.remaining(4320) == "1h 12m")
        #expect(DurationText.remaining(28800) == "8h")
    }

    @Test func statusOff() {
        #expect(StatusLine.text(leases: [], state: .off, now: now) == "Off")
    }

    @Test func statusUntilTurnedOff() {
        let leases = [lease("menu")]
        #expect(StatusLine.text(leases: leases, state: stateFor(leases), now: now) == "On · until turned off")
    }

    @Test func statusShowsScreenOnAndLongestLease() {
        let leases = [lease("a", .screenOn, left: 600), lease("b", .system, left: 4320)]
        #expect(StatusLine.text(leases: leases, state: stateFor(leases), now: now) == "On · screen on · 1h 12m left")
    }

    @Test func statusWatchedLeaseUsesReason() {
        let leases = [lease("app-42", watch: WatchedProcess(pid: 42, startTime: now), reason: "While Xcode runs")]
        #expect(StatusLine.text(leases: leases, state: stateFor(leases), now: now) == "On · while Xcode runs")
    }

    @Test func ownerLabels() {
        #expect(LeaseText.owner(.menu) == "Menu bar")
        #expect(LeaseText.owner(.cli(pid: 1)) == "Terminal")
        #expect(LeaseText.owner(.agent(name: "Claude Code")) == "Claude Code")
        #expect(LeaseText.owner(.mcp(client: "cursor")) == "cursor")
    }

    @Test func timeLeftCopy() {
        #expect(LeaseText.timeLeft(lease("a", left: 4320), now: now) == "1h 12m left")
        #expect(LeaseText.timeLeft(lease("b"), now: now) == "Until turned off")
        #expect(LeaseText.timeLeft(lease("c", watch: WatchedProcess(pid: 1, startTime: now)), now: now) == "While running")
    }
}

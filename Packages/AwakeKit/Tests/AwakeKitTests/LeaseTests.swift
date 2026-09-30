import AwakeKit
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_000_000)

struct LeaseTests {
    @Test func levelUnionIsPerFlagOR() {
        #expect(AwakeLevel.system.union(.screenOn) == .screenOn)
        #expect(AwakeLevel(display: false, lid: true).union(.screenOn) == AwakeLevel(display: true, lid: true))
    }

    @Test func leaseRoundTripsThroughJSON() throws {
        let lease = Lease(
            id: "claude-1", owner: .agent(name: "claude"), reason: "fix tests", level: .screenOn,
            expiresAt: now.addingTimeInterval(900), watch: WatchedProcess(pid: 42, startTime: now),
            endsOnLidOpen: false, createdAt: now
        )
        let decoded = try JSONDecoder().decode(Lease.self, from: JSONEncoder().encode(lease))
        #expect(decoded == lease)
    }

    @Test func leaseIsLiveUntilItsExpiry() {
        let expiry = now.addingTimeInterval(60)
        let lease = Lease(id: "a", owner: .menu, reason: "r", level: .system, expiresAt: expiry, createdAt: now)
        #expect(lease.isLive(at: expiry.addingTimeInterval(-1)))
        #expect(!lease.isLive(at: expiry))
        let forever = Lease(id: "b", owner: .menu, reason: "r", level: .system, expiresAt: nil, createdAt: now)
        #expect(forever.isLive(at: .distantFuture))
    }

    @Test func settingsDefaultsMatchSpec() {
        let settings = AwakeSettings()
        #expect(settings.clickLevel == .system)
        #expect(settings.clickDuration == nil)
        #expect(settings.endMenuLeaseAfterSleep == false)
        #expect(settings.allowLidOnBattery == false)
        #expect(settings.lidBatteryThreshold == 20)
        #expect(settings.allBatteryThreshold == 10)
        #expect(settings.thermalCutoff == true)
        #expect(settings.agentKeepAwake == .automatic)
        #expect(settings.agentLid == .askEachTime)
        #expect(settings.agentWindows == .automatic)
    }

    @Test func durationsMatchSpecOrderAndCopy() {
        #expect(AwakeDuration.allCases.map(\.title) == ["30 min", "1 h", "2 h", "4 h", "8 h", "Until turned off"])
        #expect(AwakeDuration.allCases.map(\.interval) == [1800, 3600, 7200, 14400, 28800, nil])
    }

    @Test func durationFromIntervalFallsBackToUntilTurnedOff() {
        #expect(AwakeDuration(interval: 7200) == .hours2)
        #expect(AwakeDuration(interval: nil) == .untilTurnedOff)
        #expect(AwakeDuration(interval: 999) == .untilTurnedOff)
    }
}

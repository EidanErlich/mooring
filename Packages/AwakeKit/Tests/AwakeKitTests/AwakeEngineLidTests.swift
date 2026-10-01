import AwakeKit
import Foundation
import Testing

private let lidLevel = AwakeLevel(display: false, lid: true)

@MainActor
struct AwakeEngineLidTests {
    @Test func lidLeaseAppliesThroughHelper() {
        let harness = EngineHarness()
        harness.engine.setAllowLidClose(true)
        #expect(harness.engine.menuLease?.level.lid == true)
        #expect(harness.lid.requests == [true])
        harness.lid.complete()
        #expect(harness.engine.state.lidSleepDisabled)
    }

    @Test func unavailableHelperNeverApplies() {
        let harness = EngineHarness()
        harness.lid.isAvailable = false
        harness.engine.setAllowLidClose(true)
        harness.engine.tick()
        #expect(harness.lid.requests == [])
        #expect(!harness.engine.state.lidSleepDisabled)
        #expect(harness.engine.wantsLid)
    }

    @Test func busyHelperIsNotAskedTwice() {
        let harness = EngineHarness()
        harness.engine.setAllowLidClose(true)
        harness.engine.tick()
        harness.engine.tick()
        #expect(harness.lid.requests == [true])
    }

    @Test func launchResetClearsStaleLid() {
        let harness = EngineHarness()
        harness.lid.applied = true
        _ = harness.engine
        harness.lid.onChange?()
        #expect(harness.lid.requests == [false])
    }

    @Test func restoredLidLeaseKeepsLid() {
        let harness = EngineHarness()
        harness.lid.applied = true
        harness.store.toLoad = [Lease(id: "menu", owner: .menu, reason: "r", level: lidLevel,
                                      expiresAt: nil, createdAt: harness.clock)]
        harness.engine.restore()
        #expect(harness.lid.requests == [])
        #expect(harness.engine.state.lidSleepDisabled)
    }

    @Test func guardrailPausesLidAndReports() {
        let harness = EngineHarness()
        harness.settings.allowLidOnBattery = true
        var reported: [Set<Suspension>] = []
        harness.engine.onSuspensionsAdded = { reported.append($0) }
        harness.engine.setAllowLidClose(true)
        harness.lid.complete()
        harness.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 15))
        #expect(harness.lid.requests.last == false)
        #expect(harness.engine.state.suspensions == [.lowBatteryLid])
        #expect(reported == [[.lowBatteryLid]])
    }

    @Test func lidSessionEndsWhenLidReopens() throws {
        let harness = EngineHarness()
        harness.engine.update(lidClosed: false)
        harness.engine.startLidSession()
        let lease = try #require(harness.engine.leases.first)
        #expect(lease.id == AwakeEngine.lidSessionID)
        #expect(lease.reason == "Until I open the lid")
        #expect(lease.endsOnLidOpen)
        #expect(lease.level == lidLevel)
        harness.engine.update(lidClosed: true)
        #expect(harness.engine.leases.count == 1)
        harness.engine.update(lidClosed: false)
        #expect(harness.engine.leases.isEmpty)
    }

    @Test func restoreClampsFarFutureExpiry() {
        let harness = EngineHarness()
        harness.store.toLoad = [Lease(id: "menu", owner: .menu, reason: "r", level: .system,
                                      expiresAt: harness.clock.addingTimeInterval(100 * 3600), createdAt: harness.clock)]
        harness.engine.restore()
        #expect(harness.engine.leases.first?.expiresAt == harness.clock.addingTimeInterval(12 * 3600))
    }

    @Test func thermalAndPowerUpdatesReconcile() {
        let harness = EngineHarness()
        harness.engine.update(lidClosed: true)
        harness.engine.setAllowLidClose(true)
        harness.engine.update(thermal: .critical)
        #expect(harness.engine.state.suspensions == [.thermal])
    }
}

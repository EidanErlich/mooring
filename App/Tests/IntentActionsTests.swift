import AwakeKit
import Foundation
import MooringIPC
import Testing
@testable import Mooring

/// The Shortcuts actions, through `IntentActions` so the AppIntents runtime isn't involved (stage 2c-2).
@MainActor
struct IntentActionsTests {
    private let fixture = RequestFixture()

    /// Actions over the fixture's handler.
    private func actions() -> IntentActions {
        let gate = HandlerGate()
        gate.set(fixture.handler)
        let actions = IntentActions()
        actions.gate = gate
        return actions
    }

    @Test func keepAwakeTurnsOnWithDurationAndLevel() async throws {
        // A person is trusted, so lid mode is not asked about even under Never.
        fixture.knobs.settings.agentLidApproval = .never

        _ = try await actions().keepAwake(duration: 1800, level: .lid)

        let lease = try #require(fixture.lease(AwakeEngine.menuLeaseID))
        #expect(lease.level == lidOnly)
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(1800))
        #expect(fixture.approver.calls.isEmpty)
    }

    @Test func keepAwakeWithoutDurationIsUntilTurnedOff() async throws {
        _ = try await actions().keepAwake(duration: nil, level: .normal)

        let lease = try #require(fixture.lease(AwakeEngine.menuLeaseID))
        #expect(lease.expiresAt == nil)
        #expect(lease.level == .system)
    }

    @Test func emptyDurationIgnoresClickDuration() async throws {
        fixture.knobs.settings.clickDuration = 3600

        _ = try await actions().keepAwake(duration: nil, level: .normal)

        #expect(try #require(fixture.lease(AwakeEngine.menuLeaseID)).expiresAt == nil)
    }

    /// An empty Level keeps the running session's level, as `mooring on` without `--level` does.
    @Test func emptyLevelKeepsALidSession() async throws {
        let actions = actions()
        _ = try await actions.keepAwake(duration: 1800, level: .lid)

        _ = try await actions.keepAwake(duration: nil, level: nil)

        let lease = try #require(fixture.lease(AwakeEngine.menuLeaseID))
        #expect(lease.level == lidOnly)
        #expect(lease.expiresAt == nil)
    }

    @Test func emptyLevelUsesClickLevelWhenOff() async throws {
        fixture.knobs.settings.clickLevel = .screenOn

        _ = try await actions().keepAwake(duration: 600, level: nil)

        let lease = try #require(fixture.lease(AwakeEngine.menuLeaseID))
        #expect(lease.level == .screenOn)
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(600))
    }

    /// A Shortcut that launches Mooring runs before the handler exists, and waits for it.
    @Test func requestBeforeHandlerReadyIsServed() async throws {
        let gate = HandlerGate()
        let actions = IntentActions()
        actions.gate = gate
        let running = Task { try await actions.keepAwake(duration: 600, level: .normal) }
        for _ in 0..<10 { await Task.yield() }
        #expect(fixture.lease(AwakeEngine.menuLeaseID) == nil)

        gate.set(fixture.handler)
        let text = try await running.value

        #expect(try #require(fixture.lease(AwakeEngine.menuLeaseID)).expiresAt == fixture.clock.addingTimeInterval(600))
        #expect(!text.isEmpty)
    }

    @Test func keepAwakeReturnsTheStatusSummary() async throws {
        let text = try await actions().keepAwake(duration: 600, level: .display)

        let summary = try #require(statusSummary(await fixture.send(.status)))
        #expect(text == summary)
    }

    @Test func keepAwakeReportsGuardrail() async throws {
        fixture.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 50))

        let text = try await actions().keepAwake(duration: nil, level: .lid)

        #expect(text.contains("waits for power"))
        #expect(!text.contains("mooring off"))
        #expect(fixture.lease(AwakeEngine.menuLeaseID) != nil)
    }

    @Test func letSleepEndsMenuSession() async throws {
        let actions = actions()
        _ = try await actions.keepAwake(duration: nil, level: .normal)

        try await actions.letSleep()

        #expect(fixture.lease(AwakeEngine.menuLeaseID) == nil)
    }

    @Test func statusEntityWhenOff() async throws {
        fixture.engine.update(power: PowerSnapshot(onAC: true, batteryPercent: 90))

        let entity = try await actions().status()

        #expect(!entity.isOn)
        #expect(entity.level == "off")
        #expect(entity.endsAt == nil)
        #expect(entity.onPower == true)
        #expect(entity.batteryPercent == 90)
    }

    @Test func statusEntityFields() async throws {
        fixture.engine.update(power: PowerSnapshot(onAC: true, batteryPercent: 64))
        let actions = actions()
        _ = try await actions.keepAwake(duration: 1800, level: .lid)

        let entity = try await actions.status()

        #expect(entity.isOn)
        #expect(entity.level == "lid")
        #expect(entity.endsAt == fixture.clock.addingTimeInterval(1800))
        #expect(entity.batteryPercent == 64)
        #expect(entity.onPower == true)
        #expect(entity.summary == statusSummary(await fixture.send(.status)))
    }

    @Test func appSessionCountsAsOn() async throws {
        fixture.engine.acquire(id: "app-999", owner: .menu, reason: "While Xcode runs", level: .system, duration: nil, watchPID: 999)

        let entity = try await actions().status()

        #expect(entity.isOn)
        #expect(entity.level == "off")
    }

    @Test func noGateThrowsNotReady() async {
        let actions = IntentActions()

        await #expect(throws: IntentError.notReady) { try await actions.keepAwake(duration: nil, level: .normal) }
        await #expect(throws: IntentError.notReady) { try await actions.letSleep() }
        await #expect(throws: IntentError.notReady) { _ = try await actions.status() }
        #expect(IntentError.notReady.localizedDescription == "Mooring isn't running yet")
    }

    @Test func levelsMapToWireLevels() {
        #expect(IntentLevel.normal.wire == "system")
        #expect(IntentLevel.display.wire == "display")
        #expect(IntentLevel.lid.wire == "lid")
    }

    private func statusSummary(_ response: Response) -> String? {
        if case .status(let result)? = response.result { result.summary } else { nil }
    }
}

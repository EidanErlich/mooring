import AwakeKit
import Foundation
import Testing

private let systemOnly = Applied(system: true, display: false)
private let off = Applied(system: false, display: false)

@MainActor
struct AwakeEngineTests {
    @Test func acquireAppliesSystemAssertionAndPersists() {
        let harness = EngineHarness()
        harness.engine.acquire(id: "x", owner: .menu, reason: "r", level: .system, duration: 1800)
        #expect(harness.assertions.calls == [systemOnly])
        #expect(harness.store.saved.map(\.id) == ["x"])
        #expect(harness.engine.state.systemAssertion)
    }

    @Test func reacquireRenewsKeepingCreatedAt() throws {
        let harness = EngineHarness()
        let start = harness.clock
        harness.engine.acquire(id: "x", owner: .menu, reason: "r", level: .system, duration: 1800)
        harness.advance(60)
        harness.engine.acquire(id: "x", owner: .menu, reason: "r", level: .system, duration: 1800)
        let lease = try #require(harness.engine.leases.first)
        #expect(harness.engine.leases.count == 1)
        #expect(lease.expiresAt == start.addingTimeInterval(60 + 1800))
        #expect(lease.createdAt == start)
    }

    @Test func durationsAreClampedTo12Hours() throws {
        let harness = EngineHarness()
        let result = try #require(harness.engine.acquire(id: "x", owner: .menu, reason: "r", level: .system, duration: 13 * 3600))
        #expect(result.wasClamped)
        #expect(result.lease.expiresAt == harness.clock.addingTimeInterval(12 * 3600))
    }

    @Test func releaseEndsLeaseAndAssertion() {
        let harness = EngineHarness()
        harness.engine.acquire(id: "x", owner: .menu, reason: "r", level: .system, duration: nil)
        harness.engine.release(id: "x")
        #expect(harness.assertions.calls.last == off)
        #expect(harness.engine.leases.isEmpty)
    }

    @Test func tickDropsExpiredLeases() {
        let harness = EngineHarness()
        harness.engine.acquire(id: "x", owner: .menu, reason: "r", level: .system, duration: 60)
        harness.advance(61)
        harness.engine.tick()
        #expect(harness.engine.leases.isEmpty)
        #expect(harness.assertions.calls.last == off)
    }

    @Test func reconcileAppliesOnlyChanges() {
        let harness = EngineHarness()
        harness.engine.acquire(id: "a", owner: .menu, reason: "r", level: .system, duration: nil)
        harness.engine.acquire(id: "b", owner: .menu, reason: "r", level: .system, duration: nil)
        harness.engine.tick()
        harness.engine.tick()
        #expect(harness.assertions.calls == [systemOnly])
        #expect(harness.store.saveCount == 2)
    }

    @Test func expiredLeaseEndsOnWake() {
        let harness = EngineHarness()
        harness.engine.acquire(id: "x", owner: .menu, reason: "r", level: .system, duration: 1800)
        harness.advance(7200)
        harness.engine.systemDidWake()
        #expect(harness.engine.leases.isEmpty)
        #expect(harness.assertions.calls.last == off)
    }

    /// "End my session after the Mac sleeps" ends the whole menu session (timer or
    /// picked apps), never leases from other callers.
    @Test func wakeEndsMenuSessionOnlyWhenSettingIsOn() {
        let harness = EngineHarness()
        harness.processes.startTimes[1] = harness.clock
        harness.engine.anchor(whileAppRuns: 1, appName: "Xcode")
        harness.engine.acquire(id: "cli", owner: .cli(pid: 9), reason: "r", level: .system, duration: 600)
        harness.engine.systemDidWake()
        #expect(harness.engine.leases.map(\.id) == ["app-1", "cli"])
        harness.settings.endMenuLeaseAfterSleep = true
        harness.engine.systemDidWake()
        #expect(harness.engine.leases.map(\.id) == ["cli"])
    }

    @Test func watchedProcessExitReleasesLease() throws {
        let harness = EngineHarness()
        harness.processes.startTimes[42] = harness.clock
        let lease = try #require(harness.engine.anchor(whileAppRuns: 42, appName: "Xcode"))
        #expect(lease.id == "app-42")
        #expect(lease.reason == "While Xcode runs")
        #expect(lease.expiresAt == nil)
        harness.processes.exit(42)
        #expect(harness.engine.leases.isEmpty)
    }

    @Test func anchorOnDeadProcessCreatesNothing() {
        let harness = EngineHarness()
        #expect(harness.engine.anchor(whileAppRuns: 7, appName: "Gone") == nil)
        #expect(harness.assertions.calls.isEmpty)
    }

    @Test func releaseCancelsWatch() {
        let harness = EngineHarness()
        harness.processes.startTimes[42] = harness.clock
        harness.engine.anchor(whileAppRuns: 42, appName: "Xcode")
        harness.engine.release(id: "app-42")
        #expect(harness.processes.cancelled == [42])
    }

    @Test func toggleMenuUsesClickDefaults() throws {
        let harness = EngineHarness()
        harness.settings.clickLevel = .screenOn
        harness.settings.clickDuration = 3600
        harness.engine.toggleMenu()
        let lease = try #require(harness.engine.menuLease)
        #expect(lease.id == "menu")
        #expect(lease.level == .screenOn)
        #expect(lease.owner == .menu)
        #expect(lease.reason == AwakeEngine.menuReason)
        #expect(lease.expiresAt == harness.clock.addingTimeInterval(3600))
        harness.engine.toggleMenu()
        #expect(harness.engine.menuLease == nil)
    }

    @Test func turnOnMenuKeepsCurrentLevel() {
        let harness = EngineHarness()
        harness.engine.setKeepScreenOn(true)
        harness.engine.turnOnMenu(duration: 7200)
        #expect(harness.engine.menuLease?.level == .screenOn)
        #expect(harness.engine.menuLease?.expiresAt == harness.clock.addingTimeInterval(7200))

        let fresh = EngineHarness()
        fresh.settings.clickLevel = .screenOn
        fresh.engine.turnOnMenu(duration: 1800)
        #expect(fresh.engine.menuLease?.level == .screenOn)
    }

    @Test func keepScreenOnWithoutMenuLeaseTurnsOn() {
        let harness = EngineHarness()
        harness.settings.clickDuration = 3600
        harness.engine.setKeepScreenOn(true)
        #expect(harness.engine.menuLease?.level.display == true)
        let expiry = harness.engine.menuLease?.expiresAt
        #expect(expiry == harness.clock.addingTimeInterval(3600))
        harness.advance(10)
        harness.engine.setKeepScreenOn(false)
        #expect(harness.engine.menuLease?.level.display == false)
        #expect(harness.engine.menuLease?.expiresAt == expiry)
    }

    @Test func restoreKeepsRestorableAndRewatches() {
        let harness = EngineHarness()
        let now = harness.clock
        harness.processes.startTimes[42] = now.addingTimeInterval(-60)
        harness.store.toLoad = [
            Lease(id: "menu", owner: .menu, reason: "r", level: .system, expiresAt: now.addingTimeInterval(600), createdAt: now),
            Lease(id: "old", owner: .menu, reason: "r", level: .system, expiresAt: now.addingTimeInterval(-1), createdAt: now),
            Lease(id: "app-42", owner: .menu, reason: "While Xcode runs", level: .system, expiresAt: nil,
                  watch: WatchedProcess(pid: 42, startTime: now.addingTimeInterval(-60)), createdAt: now)
        ]
        harness.engine.restore()
        #expect(harness.engine.leases.map(\.id) == ["menu", "app-42"])
        #expect(harness.assertions.calls == [systemOnly])
        harness.processes.exit(42)
        #expect(harness.engine.leases.map(\.id) == ["menu"])
    }
}

@MainActor
struct AssertionFailureTests {
    /// If IOKit refuses an assertion, the engine must not report On, and the tick retries.
    @Test func failedAssertionIsNotReportedAndIsRetried() {
        let flaky = FlakyAssertions()
        let engine = AwakeEngine(assertions: flaky, store: MemoryLeaseStore(), processes: FakeProcesses(),
                                 lid: FakeLid(), settings: { AwakeSettings() }, now: { Date(timeIntervalSince1970: 1_000_000) })
        engine.acquire(id: "x", owner: .menu, reason: "r", level: .system, duration: nil)
        #expect(!engine.state.systemAssertion)
        engine.tick()
        #expect(engine.state.systemAssertion)
        #expect(flaky.calls.count == 2)
    }
}

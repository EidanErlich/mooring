import AwakeKit
import Foundation
import MooringIPC
import Testing
@testable import Mooring

@MainActor
struct RequestHandlerTests {
    // MARK: - acquire on

    @Test func onStartsTheMenuSessionAtClickDefaults() async throws {
        let fixture = RequestFixture()
        fixture.knobs.settings.clickLevel = .screenOn
        fixture.knobs.settings.clickDuration = 3600

        let response = await fixture.acquire(.on)

        #expect(response.ok)
        #expect(response.id == "r1")
        let lease = try #require(fixture.lease("menu"))
        #expect(lease.level == .screenOn)
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(3600))
        #expect(lease.owner == .menu)
        #expect(lease.reason == AwakeEngine.menuReason)
        #expect(fixture.lease("cli") == nil)
        #expect(fixture.engine.state.displayAssertion)
        let info = try #require(acquireResult(response)).lease
        #expect(info.id == "menu")
        #expect(info.level == "display")
        #expect(info.owner == OwnerInfo(kind: "menu", name: "Menu bar"))
        #expect(info.ttl == 3600)
        #expect(acquireResult(response)?.clamped == false)
    }

    @Test func onWithFlagsOverridesDefaults() async throws {
        let fixture = RequestFixture()
        fixture.knobs.settings.clickDuration = 3600

        let response = await fixture.acquire(.on, level: "display,lid", ttl: 1800, reason: " compiling \t")

        #expect(response.ok)
        let lease = try #require(fixture.lease("menu"))
        #expect(lease.level == AwakeLevel(display: true, lid: true))
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(1800))
        #expect(lease.reason == AwakeEngine.menuReason)
        #expect(lease.owner == .menu)
    }

    @Test func onLongerThan12HoursIsClamped() async throws {
        let fixture = RequestFixture()
        let response = await fixture.acquire(.on, ttl: 24 * 3600)
        #expect(response.ok)
        #expect(acquireResult(response)?.clamped == true)
        let lease = try #require(fixture.lease("menu"))
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(AwakeEngine.maxLeaseLength))
    }

    @Test func onWithinLimitIsNotClamped() async {
        let fixture = RequestFixture()
        let response = await fixture.acquire(.on, ttl: AwakeEngine.maxLeaseLength)
        #expect(response.ok)
        #expect(acquireResult(response)?.clamped == false)
    }

    @Test func onWithUntilTurnedOffDefaultHasNoExpiry() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.on)
        #expect(try #require(fixture.lease("menu")).expiresAt == nil)
    }

    @Test func onWhileMenuSessionIsOnWithoutFlagsChangesNothing() async throws {
        let fixture = RequestFixture()
        fixture.engine.acquire(id: "menu", owner: .menu, reason: AwakeEngine.menuReason, level: .screenOn, duration: 600)
        fixture.knobs.clock.addTimeInterval(60)
        fixture.knobs.settings.clickDuration = 3600

        let response = await fixture.acquire(.on)

        let info = try #require(acquireResult(response)).lease
        #expect(info.id == "menu")
        #expect(info.level == "display")
        #expect(info.expiresAt == fixture.clock.addingTimeInterval(540))
        let lease = try #require(fixture.lease("menu"))
        #expect(lease.level == .screenOn)
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(540))
        #expect(fixture.engine.leases.map(\.id) == ["menu"])
    }

    @Test func onWithPickedAppsAndNoFlagsRepliesWithTheFirstApp() async throws {
        let fixture = RequestFixture()
        fixture.engine.anchor(whileAppRuns: 42, appName: "Xcode")
        fixture.engine.anchor(whileAppRuns: 43, appName: "Safari")

        let response = await fixture.acquire(.on)

        #expect(try #require(acquireResult(response)).lease.id == "app-42")
        #expect(fixture.engine.leases.map(\.id) == ["app-42", "app-43"])
    }

    @Test func onWithForReplacesTheMenuSession() async throws {
        let fixture = RequestFixture()
        fixture.engine.acquire(id: "menu", owner: .menu, reason: AwakeEngine.menuReason, level: .screenOn, duration: nil)

        let response = await fixture.acquire(.on, ttl: 1800)

        let lease = try #require(fixture.lease("menu"))
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(1800))
        #expect(lease.level == .screenOn)
        #expect(fixture.lease("cli") == nil)
        #expect(fixture.engine.leases.map(\.id) == ["menu"])
        #expect(try #require(acquireResult(response)).lease.ttl == 1800)
    }

    @Test func onWithLevelKeepsTheClickDurationAndTheSessionLevelOtherwise() async throws {
        let fixture = RequestFixture()
        fixture.knobs.settings.clickDuration = 3600
        fixture.engine.acquire(id: "menu", owner: .menu, reason: AwakeEngine.menuReason, level: .screenOn, duration: nil)

        _ = await fixture.acquire(.on, level: "lid")

        let lease = try #require(fixture.lease("menu"))
        #expect(lease.level == AwakeLevel(display: false, lid: true))
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(3600))
    }

    @Test func onReplacesPickedApps() async throws {
        let fixture = RequestFixture()
        fixture.engine.anchor(whileAppRuns: 42, appName: "Xcode")
        fixture.engine.anchor(whileAppRuns: 43, appName: "Safari")
        fixture.engine.setKeepScreenOn(true)

        let response = await fixture.acquire(.on, ttl: 900)

        #expect(fixture.engine.leases.map(\.id) == ["menu"])
        let lease = try #require(fixture.lease("menu"))
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(900))
        #expect(lease.level == .screenOn)
        #expect(try #require(acquireResult(response)).lease.id == "menu")
    }

    @Test func unknownLevelIsBadRequest() async {
        let fixture = RequestFixture()
        let response = await fixture.acquire(.on, level: "turbo")
        #expect(wireFailure(response) == WireError(code: .badRequest, message: "Unknown level turbo"))
        #expect(fixture.engine.leases.isEmpty)
    }

    @Test func tooManyLeasesIsDenied() async {
        let fixture = RequestFixture()
        for index in 0..<CallerPolicy.maxLeases {
            fixture.engine.acquire(id: "l\(index)", owner: .cli(pid: 1), reason: "x", level: .system, duration: nil)
        }
        let response = await fixture.acquire(.on)
        #expect(wireFailure(response)?.code == .denied)
        #expect(fixture.engine.leases.count == CallerPolicy.maxLeases)
    }

    // MARK: - acquire anchor

    @Test func anchorNeedsAWatchPid() async {
        let fixture = RequestFixture()
        let response = await fixture.acquire(.anchor)
        #expect(wireFailure(response) == WireError(code: .badRequest, message: "Missing --pid"))
        #expect(fixture.engine.leases.isEmpty)
    }

    @Test func anchorUsesAgentNameWhenGiven() async throws {
        let fixture = RequestFixture()

        let named = await fixture.acquire(.anchor, watchPid: 4242, reason: "running tests", agent: "claude-code")
        #expect(named.ok)
        let lease = try #require(fixture.lease("anchor-4242"))
        #expect(lease.owner == .agent(name: "claude-code"))
        #expect(lease.watch?.pid == 4242)
        #expect(lease.expiresAt == nil)
        #expect(lease.level == .system)
        #expect(lease.reason == "running tests")
        #expect(acquireResult(named)?.lease.watchPid == 4242)

        _ = await fixture.acquire(.anchor, watchPid: 4243)
        #expect(try #require(fixture.lease("anchor-4243")).owner == .cli(pid: 77))
    }

    @Test func anchorOfDeadProcessIsBadRequest() async {
        let fixture = RequestFixture(processes: NoProcesses())
        let response = await fixture.acquire(.anchor, watchPid: 4242)
        #expect(wireFailure(response) == WireError(code: .badRequest, message: "Process 4242 isn't running"))
        #expect(fixture.engine.leases.isEmpty)
    }

    // MARK: - acquire lease

    @Test func leaseNeedsTTLOrWatch() async {
        let fixture = RequestFixture()
        let response = await fixture.acquire(.lease, id: "job")
        #expect(wireFailure(response)?.code == .badRequest)
        #expect(fixture.engine.leases.isEmpty)
    }

    @Test func leaseNeedsAnID() async {
        let fixture = RequestFixture()
        let response = await fixture.acquire(.lease, ttl: 60)
        #expect(wireFailure(response) == WireError(code: .badRequest, message: "Missing lease id"))
    }

    @Test func leaseLidIsGrantedWhenBounded() async throws {
        let fixture = RequestFixture()
        let response = await fixture.acquire(.lease, id: "job", level: "lid", ttl: 60)
        #expect(acquireResult(response)?.lease.level == "lid")
        #expect(try #require(fixture.lease("job")).level == AwakeLevel(display: false, lid: true))
    }

    @Test func leaseTTLIsCapped() async throws {
        let fixture = RequestFixture()
        let response = await fixture.acquire(.lease, id: "job", ttl: 6 * 3600)
        #expect(response.ok)
        #expect(try #require(fixture.lease("job")).expiresAt == fixture.clock.addingTimeInterval(4 * 3600))
        #expect(acquireResult(response)?.clamped == true)
    }

    @Test func leaseDefaultsReasonToIDAndUsesAgent() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 60, agent: "codex\n")
        let lease = try #require(fixture.lease("job"))
        #expect(lease.reason == "job")
        #expect(lease.owner == .agent(name: "codex"))
        #expect(lease.level == .system)

        _ = await fixture.acquire(.lease, id: "other", ttl: 60)
        #expect(try #require(fixture.lease("other")).owner == .cli(pid: 77))
    }

    @Test func leaseWatchingADeadProcessIsBadRequest() async {
        let fixture = RequestFixture(processes: NoProcesses())
        let response = await fixture.acquire(.lease, id: "job", watchPid: 99)
        #expect(wireFailure(response) == WireError(code: .badRequest, message: "Process 99 isn't running"))
    }

    @Test func reservedIDsAreRefusedForLeaseOps() async {
        let fixture = RequestFixture()
        fixture.engine.acquire(id: "menu", owner: .menu, reason: "x", level: .system, duration: nil)

        #expect(wireFailure(await fixture.acquire(.lease, id: "menu", ttl: 60))?.code == .badRequest)
        #expect(wireFailure(await fixture.renew("menu", ttl: 60))?.code == .badRequest)
        #expect(wireFailure(await fixture.release(.lease, id: "menu"))?.code == .badRequest)
        #expect(fixture.lease("menu") != nil)
    }
}

import AwakeKit
import Foundation
import MooringIPC
import Testing
@testable import Mooring

@MainActor
struct RequestHandlerOpsTests {
    // MARK: - renew

    @Test func renewReusesTTLAndCapsIt() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 600)
        fixture.knobs.clock.addTimeInterval(100)

        let again = await fixture.renew("job")
        #expect(try #require(renewedLease(again)).expiresAt == fixture.clock.addingTimeInterval(600))
        #expect(try #require(fixture.lease("job")).expiresAt == fixture.clock.addingTimeInterval(600))

        let longer = await fixture.renew("job", ttl: 6 * 3600)
        #expect(try #require(renewedLease(longer)).expiresAt == fixture.clock.addingTimeInterval(4 * 3600))
        #expect(try #require(renewedLease(longer)).ttl == 4 * 3600)
        #expect(try #require(renewedLease(longer)).id == "job")
    }

    @Test func renewOfDroppedLeaseIsNotFound() async {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 60)
        fixture.knobs.clock.addTimeInterval(120)
        fixture.engine.tick()

        let response = await fixture.renew("job")
        #expect(wireFailure(response) == WireError(code: .notFound, message: "No lease job; acquire it again"))
    }

    // MARK: - release

    @Test func releaseIsIdempotent() async {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 60)

        let first = await fixture.release(.lease, id: "job")
        let second = await fixture.release(.lease, id: "job")

        #expect(releasedFlag(first) == true)
        #expect(releasedExpiry(first) == nil)
        #expect(releasedFlag(second) == false)
        #expect(second.ok)
        #expect(fixture.lease("job") == nil)
    }

    @Test func releaseAfterOnlyShortens() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 3600)

        let sooner = await fixture.release(.lease, id: "job", after: 60)
        #expect(releasedFlag(sooner) == true)
        #expect(try #require(fixture.lease("job")).expiresAt == fixture.clock.addingTimeInterval(60))
        #expect(releasedExpiry(sooner) == fixture.clock.addingTimeInterval(60))

        let later = await fixture.release(.lease, id: "job", after: 7200)
        #expect(try #require(fixture.lease("job")).expiresAt == fixture.clock.addingTimeInterval(60))
        #expect(releasedExpiry(later) == fixture.clock.addingTimeInterval(60))

        let missing = await fixture.release(.lease, id: "gone", after: 60)
        #expect(missing.ok)
        #expect(releasedFlag(missing) == false)
        #expect(releasedExpiry(missing) == nil)
    }

    @Test func releaseLeaseNeedsAnID() async {
        let fixture = RequestFixture()
        let response = await fixture.release(.lease)
        #expect(wireFailure(response) == WireError(code: .badRequest, message: "Missing lease id"))
    }

    @Test func offEndsTheMenuSessionAndPickedApps() async {
        let fixture = RequestFixture()
        fixture.engine.acquire(id: "menu", owner: .menu, reason: AwakeEngine.menuReason, level: .system, duration: nil)
        let first = await fixture.release(.off)
        #expect(releasedFlag(first) == true)
        #expect(fixture.engine.leases.isEmpty)

        fixture.engine.anchor(whileAppRuns: 42, appName: "Xcode")
        fixture.engine.anchor(whileAppRuns: 43, appName: "Safari")
        let second = await fixture.release(.off)
        #expect(releasedFlag(second) == true)
        #expect(fixture.engine.leases.isEmpty)
    }

    @Test func offLeavesAgentLeasesAndAnchors() async {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.on)
        _ = await fixture.acquire(.lease, id: "job", ttl: 600, agent: "claude-code")
        _ = await fixture.acquire(.anchor, watchPid: 5)

        let response = await fixture.release(.off)

        #expect(releasedFlag(response) == true)
        #expect(fixture.lease("menu") == nil)
        #expect(fixture.lease("job") != nil)
        #expect(fixture.lease("anchor-5") != nil)
    }

    @Test func offReleasesALegacyCliLease() async {
        let fixture = RequestFixture()
        fixture.engine.acquire(id: "cli", owner: .cli(pid: 1), reason: "mooring on", level: .system, duration: nil)
        fixture.engine.acquire(id: "anchor-5", owner: .cli(pid: 1), reason: "x", level: .system, duration: nil, watchPID: 5)

        let response = await fixture.release(.off)

        #expect(releasedFlag(response) == true)
        #expect(fixture.lease("cli") == nil)
        #expect(fixture.lease("anchor-5") != nil)
    }

    @Test func offWhenNothingIsOnSaysAlreadyOff() async {
        let fixture = RequestFixture()
        fixture.engine.acquire(id: "anchor-5", owner: .cli(pid: 1), reason: "x", level: .system, duration: nil, watchPID: 5)

        let response = await fixture.release(.off)

        #expect(response.ok)
        #expect(releasedFlag(response) == false)
        #expect(fixture.lease("anchor-5") != nil)
    }

    // MARK: - validation

    @Test func nonPositiveDurationsAreBadRequest() async {
        let fixture = RequestFixture()
        let expected = WireError(code: .badRequest, message: "Durations must be positive")

        #expect(wireFailure(await fixture.acquire(.on, ttl: 0)) == expected)
        #expect(wireFailure(await fixture.acquire(.lease, id: "job", ttl: -1)) == expected)
        #expect(wireFailure(await fixture.acquire(.anchor, ttl: .nan, watchPid: 5)) == expected)
        #expect(wireFailure(await fixture.renew("job", ttl: -5)) == expected)
        #expect(wireFailure(await fixture.release(.lease, id: "job", after: .infinity)) == expected)
        #expect(fixture.engine.leases.isEmpty)
    }

    // MARK: - guardrails

    private static let onSuffix = ". Mooring is on and applies when that clears; run `mooring off` to end it."

    @Test func guardrailHoldsBackLidButKeepsTheLease() async {
        let fixture = RequestFixture()
        fixture.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 5))

        let response = await fixture.acquire(.on, level: "lid")

        #expect(wireFailure(response) == WireError(code: .guardrail, message: "Paused: battery low\(Self.onSuffix)"))
        #expect(fixture.lease("menu") != nil)
    }

    @Test func guardrailMessagesFollowTheirOrder() async {
        let battery = RequestFixture()
        battery.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 15))
        let batteryReply = await battery.acquire(.on, level: "lid")
        #expect(wireFailure(batteryReply) == WireError(code: .guardrail, message: "Lid mode paused: battery low\(Self.onSuffix)"))

        let needsPower = RequestFixture()
        needsPower.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 50))
        let needsPowerReply = await needsPower.acquire(.on, level: "lid")
        #expect(wireFailure(needsPowerReply) == WireError(code: .guardrail, message: "Lid mode paused: needs power\(Self.onSuffix)"))

        let hot = RequestFixture()
        hot.engine.update(lidClosed: true)
        hot.engine.update(thermal: .serious)
        let hotReply = await hot.acquire(.on, level: "lid")
        #expect(wireFailure(hotReply) == WireError(code: .guardrail, message: "Lid mode paused: Mac too warm\(Self.onSuffix)"))
    }

    @Test func aPersonIsToldTheGuardrailInTheNotificationsWords() async {
        let fixture = RequestFixture()
        fixture.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 50))
        let args = AcquireArgs(kind: .on, id: nil, level: "lid", ttl: nil, watchPid: nil, reason: nil, agent: nil)

        let response = await fixture.handler.handle(
            Request(v: 1, id: "p", op: .acquire, args: .acquire(args)), from: Caller(uid: 501, pid: 77, identity: .person)
        )

        #expect(wireFailure(response) == WireError(
            code: .guardrail, message: "Lid mode waits for power. Mooring is on and starts when that clears."
        ))
    }

    @Test func lidGuardrailsDoNotHoldBackAPlainLease() async {
        let fixture = RequestFixture()
        fixture.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 50))
        fixture.engine.acquire(id: "lidder", owner: .menu, reason: "x", level: AwakeLevel(display: false, lid: true), duration: nil)
        #expect(fixture.engine.state.suspensions == [.lidNeedsAC])

        let response = await fixture.acquire(.on)
        #expect(response.ok)
    }

    @Test func lowBatteryHoldsBackAnyLease() async {
        let fixture = RequestFixture()
        fixture.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 5))
        let response = await fixture.acquire(.lease, id: "job", ttl: 60)
        #expect(wireFailure(response)?.code == .guardrail)
        #expect(fixture.lease("job") != nil)
    }

    @Test func leaseGuardrailMessageSaysItIsHeld() async {
        let fixture = RequestFixture()
        fixture.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 5))

        let response = await fixture.acquire(.lease, id: "job", ttl: 60)

        let expected = "Paused: battery low. Lease job is held and applies when that clears; "
            + "run `mooring lease release job` to end it."
        #expect(wireFailure(response) == WireError(code: .guardrail, message: expected))
        #expect(fixture.lease("job") != nil)
    }

    @Test func anchorGuardrailMessageSaysItApplies() async {
        let fixture = RequestFixture()
        fixture.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 5))

        let response = await fixture.acquire(.anchor, watchPid: 5)

        let expected = "Paused: battery low. The anchor applies when that clears."
        #expect(wireFailure(response) == WireError(code: .guardrail, message: expected))
        #expect(fixture.lease("anchor-5") != nil)
    }

    // MARK: - status

    @Test func statusReportsEverything() async throws {
        let fixture = RequestFixture()
        fixture.knobs.settings.lidBatteryThreshold = 70
        fixture.knobs.helperSleepDisabled = true
        fixture.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 64))
        fixture.engine.update(thermal: .fair)
        fixture.engine.update(lidClosed: false)
        fixture.engine.acquire(id: "menu", owner: .menu, reason: "Turned on from the menu bar", level: .screenOn, duration: 3600)
        fixture.engine.acquire(
            id: "anchor-9", owner: .agent(name: "claude-code"), reason: "tests", level: AwakeLevel(display: false, lid: true),
            duration: nil, watchPID: 9
        )
        fixture.engine.acquire(id: "mcp-1", owner: .mcp(client: "Cursor"), reason: "x", level: .system, duration: 600)
        _ = await fixture.acquire(.anchor, watchPid: 5)

        let response = await fixture.send(.status)

        guard case .status(let status)? = response.result else {
            Issue.record("expected a status result, got \(response)")
            return
        }
        #expect(status.summary == "On · screen on · lid mode paused · while 2 apps run")
        #expect(status.effective == LevelInfo(system: true, display: true, lid: false))
        #expect(status.systemAssertion)
        #expect(status.displayAssertion)
        #expect(!status.lidSleepDisabled)
        #expect(status.helperSleepDisabled == true)
        #expect(status.wantsLid)
        #expect(status.power == PowerInfo(onAC: false, batteryPercent: 64))
        #expect(status.thermal == "fair")
        #expect(status.lidClosed == false)
        #expect(status.helper == "enabled")
        #expect(status.suspensions == ["lidNeedsAC", "lowBatteryLid"])
        #expect(status.leases.map(\.id) == ["menu", "anchor-9", "mcp-1", "anchor-5"])

        let menu = status.leases[0]
        #expect(menu.owner == OwnerInfo(kind: "menu", name: "Menu bar"))
        #expect(menu.level == "display")
        #expect(menu.expiresAt == fixture.clock.addingTimeInterval(3600))
        #expect(menu.ttl == 3600)
        #expect(menu.watchPid == nil)
        let anchor = status.leases[1]
        #expect(anchor.owner == OwnerInfo(kind: "agent", name: "claude-code"))
        #expect(anchor.level == "lid")
        #expect(anchor.watchPid == 9)
        #expect(anchor.expiresAt == nil)
        #expect(status.leases[2].owner == OwnerInfo(kind: "mcp", name: "Cursor"))
        #expect(status.leases[3].owner == OwnerInfo(kind: "cli", name: "Terminal"))
    }

    @Test func statusWhenIdleHasUnknownHelperState() async {
        let fixture = RequestFixture()
        let response = await fixture.send(.status)
        guard case .status(let status)? = response.result else {
            Issue.record("expected a status result, got \(response)")
            return
        }
        #expect(status.summary == "Off")
        #expect(status.helperSleepDisabled == nil)
        #expect(status.leases.isEmpty)
        #expect(status.thermal == "nominal")
        #expect(status.lidClosed == nil)
        #expect(status.suspensions.isEmpty)
        #expect(status.effective == LevelInfo(system: false, display: false, lid: false))
    }

    @Test func statusListsOnlyLiveLeases() async {
        let fixture = RequestFixture()
        fixture.engine.acquire(id: "job", owner: .cli(pid: 5), reason: "x", level: .system, duration: 60)
        fixture.knobs.clock = fixture.clock.addingTimeInterval(120)
        let response = await fixture.send(.status)
        guard case .status(let status)? = response.result else {
            Issue.record("expected a status result, got \(response)")
            return
        }
        #expect(status.leases.isEmpty)
    }
}

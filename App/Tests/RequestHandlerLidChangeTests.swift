import AwakeKit
import Foundation
import MooringIPC
import Testing
@testable import Mooring

/// Lid asks that an existing lease, or a change to it while the person decides, must not get around.
@MainActor
struct RequestHandlerLidChangeTests {
    // MARK: - an existing lease with lid

    @Test func boundedLidOnThenOpenEndedOnStillAsks() async throws {
        let fixture = RequestFixture.agent()
        fixture.approver.answers = [.deny]

        let bounded = await fixture.acquire(.on, level: "lid", ttl: 60)
        let openEnded = await fixture.acquire(.on, level: "lid")

        #expect(bounded.ok)
        #expect(wireFailure(openEnded) == denied("Lid mode not approved (denied)"))
        #expect(fixture.approver.calls.count == 1)
        let lease = try #require(fixture.lease("menu"))
        #expect(lease.level == .system)
        #expect(lease.expiresAt == nil)
    }

    @Test func personsBoundedLidSessionDoesNotLetAnAgentGoOpenEnded() async throws {
        let timed = RequestFixture.agent()
        timed.engine.turnOnMenu(duration: 600, level: lidOnly)
        let apps = RequestFixture.agent()
        apps.engine.acquire(
            id: "app-999", owner: .menu, reason: "While Xcode runs", level: lidOnly, duration: nil, watchPID: 999
        )

        for fixture in [timed, apps] {
            fixture.approver.answers = [.deny]
            let response = await fixture.acquire(.on, level: "lid")
            #expect(wireFailure(response) == denied("Lid mode not approved (denied)"))
            #expect(fixture.approver.calls.count == 1)
            let lease = try #require(fixture.lease("menu"))
            #expect(lease.level == .system)
            #expect(lease.expiresAt == nil)
        }
    }

    // MARK: - the lease changing during an ask

    @Test func allowAfterTheRequestChangedDoesNotUpgrade() async throws {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .alwaysAsk
        fixture.approver.holds = true

        let ask = Task { await fixture.acquire(.on, level: "lid", ttl: 600) }
        await fixture.approver.waitForCalls(1)
        #expect(fixture.approver.calls.first?.body == "\(AwakeEngine.menuReason) · for 10m")
        let widened = await fixture.acquire(.on, level: "system")
        fixture.approver.resolve("menu", with: .allowOnce)

        #expect(widened.ok)
        #expect(wireFailure(await ask.value) == denied("Lid mode not approved (the request changed while you were deciding)"))
        let lease = try #require(fixture.lease("menu"))
        #expect(lease.level == .system)
        #expect(lease.expiresAt == nil)
    }

    @Test func allowAfterMenuRestartedDoesNotUpgradeTheNewSession() async throws {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .alwaysAsk
        fixture.approver.holds = true

        let ask = Task { await fixture.acquire(.on, level: "lid", ttl: 600) }
        await fixture.approver.waitForCalls(1)
        fixture.engine.endMenuSession()
        fixture.advance(1)
        fixture.engine.turnOnMenu(duration: 300, level: .system)
        fixture.approver.resolve("menu", with: .allowOnce)

        #expect(wireFailure(await ask.value) == denied("Lid mode not approved (the request changed while you were deciding)"))
        #expect(try #require(fixture.lease("menu")).level == .system)
    }

    @Test func allowOnUnchangedLeaseUpgrades() async throws {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .alwaysAsk
        fixture.approver.holds = true

        let timed = Task { await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600) }
        await fixture.approver.waitForCalls(1)
        let watched = Task { await fixture.acquire(.lease, id: "job-w", level: "lid", ttl: 600, watchPid: 4242) }
        await fixture.approver.waitForCalls(2)
        // A shorter re-acquire keeps the expiry; a watched lease's end is its process, so renewing it is fine.
        _ = await fixture.acquire(.lease, id: "job", ttl: 300)
        _ = await fixture.renew("job-w", ttl: 1200)
        fixture.approver.resolve("job", with: .allowOnce)
        fixture.approver.resolve("job-w", with: .allowOnce)

        #expect(await timed.value.ok)
        #expect(await watched.value.ok)
        #expect(try #require(fixture.lease("job")).level == lidOnly)
        #expect(try #require(fixture.lease("job-w")).level == lidOnly)
    }
}

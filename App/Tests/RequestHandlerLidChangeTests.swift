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

        // The person's session is left as it is, bounded, while the agent is asked about, then denied.
        for (fixture, id) in [(timed, "menu"), (apps, "app-999")] {
            let before = try #require(fixture.lease(id))
            fixture.approver.answers = [.deny]
            let response = await fixture.acquire(.on, level: "lid")
            #expect(wireFailure(response) == denied("Lid mode not approved (denied)"))
            #expect(fixture.approver.calls.count == 1)
            #expect(fixture.engine.leases == [before])
        }
    }

    // MARK: - a person's lid

    @Test func neverKeepsAPersonsLidLease() async throws {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .never
        fixture.engine.acquire(id: "job", owner: .cli(pid: 1), reason: "mine", level: lidOnly, duration: 3600)
        let before = try #require(fixture.lease("job"))

        let response = await fixture.acquire(.lease, id: "job", level: "lid", ttl: 4 * 3600, reason: "agent's")

        #expect(wireFailure(response) == denied("Lid mode not approved (lid mode for agents is set to Never) Your lease is unchanged."))
        #expect(fixture.lease("job") == before)
    }

    @Test func neverKeepsAPersonsLidSession() async throws {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .never
        fixture.engine.turnOnMenu(duration: 2 * 3600, level: lidOnly)
        let before = try #require(fixture.lease("menu"))

        let response = await fixture.acquire(.on, level: "lid", ttl: 3600)

        #expect(wireFailure(response) == denied("Lid mode not approved (lid mode for agents is set to Never) Your lease is unchanged."))
        #expect(fixture.lease("menu") == before)
    }

    @Test func neverKeepsAPersonsLidAnchor() async throws {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .never
        fixture.engine.acquire(
            id: "anchor-4242", owner: .cli(pid: 1), reason: "mine", level: lidOnly, duration: nil, watchPID: 4242
        )
        let before = try #require(fixture.lease("anchor-4242"))

        let response = await fixture.acquire(.anchor, level: "lid", watchPid: 4242, reason: "agent's")

        #expect(wireFailure(response) == denied("Lid mode not approved (lid mode for agents is set to Never) Your lease is unchanged."))
        #expect(fixture.lease("anchor-4242") == before)
    }

    @Test func askLeavesAPersonsLidLeaseAlone() async throws {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .alwaysAsk
        fixture.approver.holds = true
        fixture.engine.turnOnMenu(duration: 2 * 3600, level: lidOnly)
        let before = try #require(fixture.lease("menu"))

        let ask = Task { await fixture.acquire(.on, level: "lid") }
        await fixture.approver.waitForCalls(1)
        #expect(fixture.lease("menu") == before)
        fixture.approver.resolve("menu", with: .allowOnce)

        #expect(acquireResult(await ask.value)?.lease.level == "lid")
        #expect(fixture.lease("menu") == before)
        // The lid is still the person's, so Never doesn't take it back.
        fixture.knobs.settings.agentLidApproval = .never
        fixture.handler.applyLidSettings()
        #expect(fixture.lease("menu") == before)
    }

    @Test func neverLeavesAgentGrantedLidRemovable() async throws {
        let fixture = RequestFixture.agent()
        _ = await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600)
        #expect(try #require(fixture.lease("job")).level == lidOnly)
        fixture.knobs.settings.agentLidApproval = .never

        let response = await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600)

        #expect(wireFailure(response) == denied("Lid mode not approved (lid mode for agents is set to Never)"))
        #expect(try #require(fixture.lease("job")).level == .system)
    }

    @Test func appsWithAPersonsLidAreAskedAboutOnce() async throws {
        let fixture = RequestFixture.agent()
        fixture.approver.holds = true
        fixture.engine.acquire(
            id: "app-999", owner: .menu, reason: "While Xcode runs", level: lidOnly, duration: nil, watchPID: 999
        )

        let first = Task { await fixture.acquire(.on, level: "lid") }
        await fixture.approver.waitForCalls(1)
        // Not awaited directly: a second ask would hold it until the end.
        let second = ReplyBox()
        Task { second.reply = await fixture.acquire(.on, level: "lid") }
        await fixture.waitUntil { second.reply != nil || fixture.approver.calls.count > 1 }

        let waiting = "Lid mode not approved (waiting for your answer to an earlier request) Your lease is unchanged."
        #expect(second.reply.flatMap(wireFailure) == denied(waiting))
        #expect(fixture.approver.calls.map(\.leaseID) == ["app-999"])
        fixture.approver.resolve("app-999", with: .deny)
        #expect(wireFailure(await first.value) == denied("Lid mode not approved (denied)"))
    }

    // MARK: - the lease changing during an ask

    /// The ask names the watched process by the program it runs, so npm Claude Code isn't "node".
    @Test func approvalBodyNamesTheProgramOfAWatchedNodeClaude() async throws {
        var table = FakeProcessTable([(200, "sh"), (100, "claude")])
        table.entries[4242] = ProcessEntry(pid: 4242, parent: 100, name: "node")
        table.commandLines[4242] = ["claude", "", ""]
        table.entries[4343] = ProcessEntry(pid: 4343, parent: 100, name: "node")
        table.commandLines[4343] = ["node", "/usr/local/bin/vite"]
        let fixture = RequestFixture(table: table, callerPID: 200)
        fixture.knobs.settings.agentLidApproval = .alwaysAsk
        fixture.approver.holds = true

        let titled = Task { await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600, watchPid: 4242, reason: "build") }
        await fixture.approver.waitForCalls(1)
        let other = Task { await fixture.acquire(.lease, id: "dev", level: "lid", ttl: 600, watchPid: 4343, reason: "serve") }
        await fixture.approver.waitForCalls(2)

        #expect(fixture.approver.calls.map(\.body) == ["build · while claude runs", "serve · while node runs"])
        fixture.approver.resolve("job", with: .deny)
        fixture.approver.resolve("dev", with: .deny)
        _ = await (titled.value, other.value)
    }

    @Test func allowAfterTheRequestChangedDoesNotUpgrade() async throws {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .alwaysAsk
        fixture.approver.holds = true

        let ask = Task { await fixture.acquire(.on, level: "lid", ttl: 600) }
        await fixture.approver.waitForCalls(1)
        #expect(fixture.approver.calls.first?.body == "mooring on · for 10m")
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

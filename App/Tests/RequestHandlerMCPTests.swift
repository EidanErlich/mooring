import AwakeKit
import Foundation
import MooringIPC
import Testing
@testable import Mooring

/// MCP leases and callers whose identity is given rather than detected (stage 2c-2).
@MainActor
struct RequestHandlerMCPTests {
    /// A lid lease the MCP server acquires for `client`, ending by its ttl and watching the caller.
    private func mcpAcquire(
        _ fixture: RequestFixture, id: String = "mcp-claude-desktop-1", client: String? = "claude-ai", reason: String? = nil
    ) async -> Response {
        await fixture.send(.acquire(AcquireArgs(
            kind: .lease, id: id, level: "lid", ttl: 1200, watchPid: fixture.caller.pid, reason: reason, agent: nil,
            client: client
        )))
    }

    /// `on --level lid`, open-ended, from `caller`.
    private func turnOnLid(_ fixture: RequestFixture, from caller: Caller) async -> Response {
        let args = AcquireArgs(kind: .on, id: nil, level: "lid", ttl: nil, watchPid: nil, reason: nil, agent: nil)
        return await fixture.handler.handle(Request(v: 1, id: "r2", op: .acquire, args: .acquire(args)), from: caller)
    }

    @Test func mcpAcquireIsAnAgentEvenFromAPersonAncestry() async throws {
        let fixture = RequestFixture()
        fixture.knobs.settings.agentLidApproval = .alwaysAsk

        _ = await mcpAcquire(fixture)

        #expect(fixture.approver.calls.map(\.agent) == ["Claude Desktop"])
        #expect(try #require(fixture.lease("mcp-claude-desktop-1")).owner == .mcp(client: "Claude Desktop"))
    }

    @Test func extendingAnMCPLeaseKeepsItsReason() async throws {
        let fixture = RequestFixture()
        _ = await mcpAcquire(fixture, reason: "build")
        fixture.knobs.clock.addTimeInterval(600)

        #expect(await mcpAcquire(fixture).ok)
        #expect(try #require(fixture.lease("mcp-claude-desktop-1")).reason == "build")
    }

    @Test func extendingAnExpiredMCPLeaseStillNamesTheClient() async throws {
        let fixture = RequestFixture()
        _ = await mcpAcquire(fixture, reason: "build")
        // Expired, but not yet ticked away: the extension, which sends no reason, starts a fresh lease.
        fixture.knobs.clock.addTimeInterval(1201)

        #expect(await mcpAcquire(fixture).ok)
        #expect(try #require(fixture.lease("mcp-claude-desktop-1")).reason == "Requested by Claude Desktop")

        // Other callers keep the id.
        _ = await fixture.acquire(.lease, id: "job", ttl: 600)
        #expect(try #require(fixture.lease("job")).reason == "job")
    }

    @Test func mcpLidWithEndNeedsNoPromptByDefault() async throws {
        let fixture = RequestFixture()

        let response = await mcpAcquire(fixture)

        #expect(response.ok)
        #expect(try #require(fixture.lease("mcp-claude-desktop-1")).level == lidOnly)
        #expect(fixture.approver.calls.isEmpty)
    }

    @Test func clientLeaseGuardrailNamesReleaseAwake() async {
        let fixture = RequestFixture()
        fixture.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 15))

        let response = await mcpAcquire(fixture)

        #expect(wireFailure(response) == WireError(
            code: .guardrail,
            message: "Lid mode paused: battery low. The lease is held and resumes when that clears; call release_awake to end it."
        ))
        #expect(fixture.lease("mcp-claude-desktop-1") != nil)
    }

    @Test func plainLeaseGuardrailKeepsCLIWording() async {
        let fixture = RequestFixture()
        fixture.engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 5))

        let response = await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600)

        #expect(wireFailure(response)?.message
            == "Paused: battery low. Lease job is held and applies when that clears; run `mooring lease release job` to end it.")
    }

    @Test func clientNeedsMcpPrefix() async {
        let fixture = RequestFixture()

        let response = await mcpAcquire(fixture, id: "job-x")

        #expect(wireFailure(response)?.code == .badRequest)
        #expect(fixture.lease("job-x") == nil)
    }

    @Test func mcpPrefixNeedsClient() async {
        let fixture = RequestFixture()

        let response = await mcpAcquire(fixture, id: "mcp-x-1", client: nil)

        #expect(wireFailure(response) == WireError(code: .badRequest, message: "mcp- ids are for MCP clients"))
        #expect(fixture.lease("mcp-x-1") == nil)
    }

    @Test func emptyClientIsAnMCPClient() async throws {
        // `mooring mcp` sends "" before `initialize` names the client.
        let fixture = RequestFixture()

        let response = await mcpAcquire(fixture, id: "mcp-mcp-client-500-1", client: "")

        #expect(response.ok)
        #expect(try #require(fixture.lease("mcp-mcp-client-500-1")).owner == .mcp(client: "MCP client"))

        #expect(await fixture.notify("One", client: "").ok)
        fixture.knobs.clock += 5
        #expect(wireFailure(await fixture.notify("Two", client: "")) == denied("Rate-limited: try again in 25 s"))
        #expect(fixture.poster.posts.map(\.title) == ["MCP client: One"])
    }

    @Test func clientWatchingUnrelatedPidAsks() async {
        // pid 1 isn't the MCP server or under it, so the watch is no end: open-ended lid is asked about.
        let fixture = RequestFixture()

        _ = await fixture.send(.acquire(AcquireArgs(
            kind: .lease, id: "mcp-x-1", level: "lid", ttl: nil, watchPid: 1, reason: nil, agent: nil, client: "claude-ai"
        )))

        #expect(fixture.approver.calls.map(\.agent) == ["Claude Desktop"])
    }

    @Test func forcedPersonNeverAsks() async throws {
        // The ancestry says Claude Code; the forced identity wins.
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .alwaysAsk

        let response = await turnOnLid(fixture, from: Caller(uid: 501, pid: 200, identity: .person))

        #expect(response.ok)
        #expect(try #require(fixture.lease("menu")).level == lidOnly)
        #expect(fixture.approver.calls.isEmpty)
    }

    @Test func forcedAgentIsAsked() async {
        let fixture = RequestFixture()

        _ = await turnOnLid(fixture, from: Caller(uid: 501, pid: 77, identity: .agent("Raycast")))

        #expect(fixture.approver.calls.map(\.agent) == ["Raycast"])
    }
}

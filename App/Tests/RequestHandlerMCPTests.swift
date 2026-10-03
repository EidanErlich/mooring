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
        _ fixture: RequestFixture, id: String = "mcp-claude-desktop-1", client: String? = "claude-ai"
    ) async -> Response {
        await fixture.send(.acquire(AcquireArgs(
            kind: .lease, id: id, level: "lid", ttl: 1200, watchPid: fixture.caller.pid, reason: nil, agent: nil,
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

    @Test func mcpLidWithEndNeedsNoPromptByDefault() async throws {
        let fixture = RequestFixture()

        let response = await mcpAcquire(fixture)

        #expect(response.ok)
        #expect(try #require(fixture.lease("mcp-claude-desktop-1")).level == lidOnly)
        #expect(fixture.approver.calls.isEmpty)
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

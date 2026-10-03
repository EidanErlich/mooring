import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

// MARK: - Protocol

@Test func initializeEchoesSupportedVersion() async {
    let harness = MCPHarness()
    _ = await harness.run([initialize(version: "2025-03-26")])
    let result = harness.reply(1)?["result"] as? [String: Any]
    #expect(result?["protocolVersion"] as? String == "2025-03-26")
    #expect(harness.reply(1)?["jsonrpc"] as? String == "2.0")
}

@Test func initializeFallsBackToNewest() async {
    let harness = MCPHarness()
    _ = await harness.run([initialize(version: "1999-01-01")])
    let result = harness.reply(1)?["result"] as? [String: Any]
    #expect(result?["protocolVersion"] as? String == "2025-06-18")
}

@Test func initializeReportsToolsCapabilityAndServerInfo() async {
    let harness = MCPHarness()
    _ = await harness.run([initialize()])
    let result = harness.reply(1)?["result"] as? [String: Any]
    let capabilities = result?["capabilities"] as? [String: Any]
    #expect(capabilities?.keys.sorted() == ["tools"])
    #expect((capabilities?["tools"] as? [String: Any])?.isEmpty == true)
    let info = result?["serverInfo"] as? [String: Any]
    #expect(info?["name"] as? String == "mooring")
    #expect(info?["version"] as? String == MCPHarness.appVersion)
}

@Test func repliesAreOneCompactLineEach() async {
    let harness = MCPHarness()
    _ = await harness.run([initialize(), rpc(2, "ping"), rpc(3, "tools/list")])
    let output = harness.capture.stdout
    #expect(output.hasSuffix("\n"))
    #expect(output.split(separator: "\n").count == 3)
    #expect(!output.contains("\n  "))
}

@Test func notificationGetsNoReply() async {
    let harness = MCPHarness()
    let code = await harness.run([#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#])
    #expect(code == 0)
    #expect(harness.capture.stdout.isEmpty)
}

@Test func unknownMethodIs32601() async {
    let harness = MCPHarness()
    _ = await harness.run([rpc(7, "resources/list")])
    let error = harness.reply(7)?["error"] as? [String: Any]
    #expect(error?["code"] as? Int == -32601)
}

@Test func badLineIs32700() async {
    let harness = MCPHarness()
    let overlong = #"{"jsonrpc":"2.0","id":1,"method":"ping","params":{"pad":""# + String(repeating: "x", count: 1_048_577) + #""}}"#
    _ = await harness.run(["this is not json", overlong])
    let replies = harness.replies
    #expect(replies.count == 2)
    for reply in replies {
        #expect((reply["error"] as? [String: Any])?["code"] as? Int == -32700)
        #expect(reply["id"] is NSNull)
    }
}

@Test func badLineKeepsServing() async {
    let harness = MCPHarness()
    let code = await harness.run(["{bad", rpc(2, "ping")])
    #expect(code == 0)
    #expect(harness.replies.count == 2)
    #expect((harness.replies.first?["error"] as? [String: Any])?["code"] as? Int == -32700)
    #expect((harness.reply(2)?["result"] as? [String: Any])?.isEmpty == true)
}

@Test func unknownToolIs32602() async {
    let harness = MCPHarness()
    _ = await harness.run([initialize(), call(2, "copy_text")])
    #expect((harness.reply(2)?["error"] as? [String: Any])?["code"] as? Int == -32602)
    #expect(harness.allRequests.isEmpty)
}

@Test func eofReturnsZero() async {
    let harness = MCPHarness()
    #expect(await harness.run([]) == 0)
    #expect(harness.capture.stdout.isEmpty)
}

@Test func toolsCallBeforeInitializeIsServed() async {
    let harness = MCPHarness()
    _ = await harness.run([call(1, "keep_awake", #"{"minutes":5}"#), call(2, "awake_status")])
    #expect(harness.isError(1) == false)
    #expect(harness.isError(2) == false)
    let args = acquireArgs(of: harness.client.requests.first)
    #expect(args?.id == "mcp-mcp-client-500-1")
    #expect(args?.client == "")
    #expect(args?.reason == "Requested by MCP client")
    #expect(harness.client.requests.last?.op == .status)
}

@Test func toolsListIsExactlyFourTools() async throws {
    let harness = MCPHarness()
    _ = await harness.run([initialize(), rpc(2, "tools/list")])
    let tools = try #require((harness.reply(2)?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
    #expect(tools.compactMap { $0["name"] as? String } == ["keep_awake", "release_awake", "awake_status", "notify"])
    for tool in tools {
        let name = tool["name"] as? String ?? ""
        let description = tool["description"] as? String ?? ""
        #expect(!description.isEmpty)
        #expect(tool["inputSchema"] is [String: Any])
        #expect(!name.lowercased().contains("clipboard"))
        #expect(!description.lowercased().contains("clipboard"))
    }
}

// MARK: - keep_awake

@Test func keepAwakeSendsLeaseWithClientTtlAndWatch() async throws {
    let harness = MCPHarness()
    _ = await harness.run([initialize(), call(2, "keep_awake", #"{"minutes":20,"level":"lid"}"#)])
    #expect(harness.client.requests.isEmpty)
    let request = try #require(harness.lidClient.requests.first)
    #expect(request.op == .acquire)
    #expect(acquireArgs(of: request) == AcquireArgs(
        kind: .lease, id: "mcp-claude-desktop-500-1", level: "lid", ttl: 1200, watchPid: MCPHarness.defaultPID,
        reason: "Requested by Claude Desktop", agent: nil, client: "claude-ai"
    ))
    #expect(harness.isError(2) == false)
    #expect(harness.text(2)?.contains("mcp-claude-desktop-500-1") == true)
    #expect(harness.text(2)?.contains("lid mode") == true)
    // One shape for every success; `guardrail` only when the lease is held.
    let structured = try #require(harness.structured(2))
    #expect(structured.keys.sorted() == ["ends_at", "lease_id", "level"])
    #expect(structured["lease_id"] as? String == "mcp-claude-desktop-500-1")
    #expect(structured["level"] as? String == "lid")
    #expect(structured["ends_at"] as? String == ISO8601DateFormatter().string(from: fixedNow.addingTimeInterval(1200)))
}

@Test func keepAwakeNumbersLeasesAndDefaultsToSystem() async {
    let harness = MCPHarness()
    _ = await harness.run([
        initialize(), call(2, "keep_awake", #"{"minutes":5,"reason":"build"}"#), call(3, "keep_awake", #"{"minutes":240}"#)
    ])
    #expect(harness.lidClient.requests.isEmpty)
    let args = harness.client.requests.compactMap { acquireArgs(of: $0) }
    #expect(args.map(\.id) == ["mcp-claude-desktop-500-1", "mcp-claude-desktop-500-2"])
    #expect(args.map(\.level) == ["system", "system"])
    #expect(args.map(\.ttl) == [300, 14_400])
    #expect(args.first?.reason == "build")
}

@Test func twoServersForOneClientGetDistinctIds() async {
    let first = MCPHarness()
    var second = MCPHarness()
    second.ownPID = 501
    for harness in [first, second] {
        _ = await harness.run([initialize("claude-code"), call(2, "keep_awake", #"{"minutes":5}"#)])
    }
    let firstID = acquireArgs(of: first.client.requests.first)?.id
    let secondID = acquireArgs(of: second.client.requests.first)?.id
    #expect(firstID == "mcp-claude-code-500-1")
    #expect(secondID == "mcp-claude-code-501-1")
    #expect(acquireArgs(of: second.client.requests.first)?.watchPid == 501)
}

@Test func leaseIdsFitTheIdLimit() async throws {
    var harness = MCPHarness()
    harness.ownPID = .max
    _ = await harness.run([initialize(String(repeating: "x", count: 60)), call(2, "keep_awake", #"{"minutes":5}"#)])
    let id = try #require(acquireArgs(of: harness.client.requests.first)?.id)
    #expect(id == "mcp-\(String(repeating: "x", count: 24))-2147483647-1")
    #expect(id.count <= 64)
}

@Test func keepAwakeGuardrailIsHeldNotError() async throws {
    let message = "Lid mode paused: battery low. The lease is held and resumes when that clears; call release_awake to end it."
    var harness = MCPHarness()
    harness.lidClient = ScriptedClient { .success(.failure(id: $0.id, .guardrail, message)) }
    _ = await harness.run([initialize(), call(2, "keep_awake", #"{"minutes":20,"level":"lid"}"#), call(3, "release_awake")])
    #expect(harness.isError(2) == false)
    let text = try #require(harness.text(2))
    #expect(text.contains("mcp-claude-desktop-500-1"))
    #expect(text.contains(message))
    #expect(!text.contains("\n"))
    let structured = try #require(harness.structured(2))
    #expect(structured["lease_id"] as? String == "mcp-claude-desktop-500-1")
    #expect(structured["level"] as? String == "lid")
    #expect(structured["ends_at"] as? String == ISO8601DateFormatter().string(from: fixedNow.addingTimeInterval(1200)))
    #expect(structured["guardrail"] as? String == message)
    #expect(structured.keys.sorted() == ["ends_at", "guardrail", "lease_id", "level"])
    // The app holds the lease, so it is this client's to release.
    #expect(harness.text(3) == "Released mcp-claude-desktop-500-1")
}

@Test func keepAwakeRejectsMinutesOutOfRange() async {
    let harness = MCPHarness()
    _ = await harness.run([
        initialize(),
        call(2, "keep_awake", #"{"minutes":0}"#), call(3, "keep_awake", #"{"minutes":241}"#),
        call(4, "keep_awake", #"{"minutes":2.5}"#), call(5, "keep_awake", #"{"minutes":"20"}"#), call(6, "keep_awake")
    ])
    for id in 2...6 {
        #expect(harness.isError(id) == true)
        #expect(harness.text(id) == "minutes must be a whole number from 1 to 240")
    }
    #expect(harness.allRequests.isEmpty)
}

@Test func keepAwakeRejectsUnknownLevel() async {
    let harness = MCPHarness()
    _ = await harness.run([initialize(), call(2, "keep_awake", #"{"minutes":5,"level":"turbo"}"#)])
    #expect(harness.isError(2) == true)
    #expect(harness.text(2) == "unknown level 'turbo'")
    #expect(harness.allRequests.isEmpty)
}

@Test func keepAwakeWithForeignLeaseIdIsError() async {
    let harness = MCPHarness()
    _ = await harness.run([
        initialize(), call(2, "keep_awake", #"{"minutes":5,"lease_id":"job"}"#),
        call(3, "keep_awake", #"{"minutes":5}"#), call(4, "keep_awake", #"{"minutes":30,"lease_id":"mcp-claude-desktop-500-1"}"#)
    ])
    #expect(harness.isError(2) == true)
    #expect(harness.text(2) == "not one of this client's leases")
    let args = harness.client.requests.compactMap { acquireArgs(of: $0) }
    #expect(args.map(\.id) == ["mcp-claude-desktop-500-1", "mcp-claude-desktop-500-1"])
    #expect(args.last?.ttl == 1800)
}

// MARK: - release_awake

@Test func releaseWithoutIdReleasesOnlyOwnLeases() async {
    let harness = MCPHarness()
    _ = await harness.run([
        initialize(), call(2, "keep_awake", #"{"minutes":5}"#), call(3, "keep_awake", #"{"minutes":5}"#),
        call(4, "release_awake", #"{"lease_id":"job"}"#), call(5, "release_awake"), call(6, "release_awake")
    ])
    #expect(harness.isError(4) == true)
    #expect(harness.text(4) == "not one of this client's leases")
    let releases = harness.client.requests.compactMap { request -> ReleaseArgs? in
        if case .release(let args) = request.args { return args }
        return nil
    }
    #expect(releases == [
        ReleaseArgs(kind: .lease, id: "mcp-claude-desktop-500-1", after: nil),
        ReleaseArgs(kind: .lease, id: "mcp-claude-desktop-500-2", after: nil)
    ])
    #expect(harness.isError(5) == false)
    #expect(harness.text(5) == "Released mcp-claude-desktop-500-1; Released mcp-claude-desktop-500-2")
    #expect(harness.isError(6) == false)
    #expect(harness.text(6) == "No leases to release")
}

@Test func releaseWithIdReleasesThatLeaseOnly() async {
    let harness = MCPHarness()
    _ = await harness.run([
        initialize(), call(2, "keep_awake", #"{"minutes":5}"#), call(3, "keep_awake", #"{"minutes":5}"#),
        call(4, "release_awake", #"{"lease_id":"mcp-claude-desktop-500-2"}"#),
        call(5, "release_awake", #"{"lease_id":"mcp-claude-desktop-500-2"}"#)
    ])
    #expect(harness.text(4) == "Released mcp-claude-desktop-500-2")
    #expect(harness.isError(5) == true)
    #expect(harness.client.requests.filter { $0.op == .release }.count == 1)
}

// MARK: - Errors from the app

@Test func deniedBecomesIsErrorWithMessage() async {
    var harness = MCPHarness()
    harness.lidClient = ScriptedClient { .success(.failure(id: $0.id, .denied, "Lid mode not approved (denied)")) }
    _ = await harness.run([initialize(), call(2, "keep_awake", #"{"minutes":20,"level":"lid"}"#), call(3, "release_awake")])
    #expect(harness.isError(2) == true)
    #expect(harness.text(2) == "Lid mode not approved (denied)")
    // A denied lease was never held, so there is nothing to release.
    #expect(harness.text(3) == "No leases to release")
}

@Test func unreachableAppBecomesIsError() async {
    var harness = MCPHarness()
    harness.client = ScriptedClient { _ in .failure(.unreachable) }
    _ = await harness.run([initialize(), call(2, "awake_status")])
    #expect(harness.isError(2) == true)
    #expect(harness.text(2) == "Mooring isn't running and couldn't be started")
}

// MARK: - awake_status

@Test func statusListsOnlyThisServersLeases() async throws {
    let mine = leaseInfo(id: "mcp-claude-desktop-500-1", owner: OwnerInfo(kind: "mcp", name: "Claude Desktop"),
                         level: "lid", expiresAt: fixedNow.addingTimeInterval(1200), watchPid: MCPHarness.defaultPID)
    let otherWindow = leaseInfo(id: "mcp-claude-desktop-999-1", owner: OwnerInfo(kind: "mcp", name: "Claude Desktop"), watchPid: 999)
    let otherClient = leaseInfo(id: "mcp-cursor-1", owner: OwnerInfo(kind: "mcp", name: "Cursor"), watchPid: MCPHarness.defaultPID)
    let agent = leaseInfo(id: "job", owner: OwnerInfo(kind: "agent", name: "Claude Desktop"), watchPid: MCPHarness.defaultPID)
    let status = statusResult(leases: [mine, otherWindow, otherClient, agent])
    var harness = MCPHarness()
    harness.client = ScriptedClient { .success(.success(id: $0.id, .status(status))) }
    _ = await harness.run([initialize(), call(2, "awake_status")])
    #expect(harness.client.requests.map(\.op) == [.status])
    #expect(harness.isError(2) == false)
    let text = try #require(harness.text(2))
    let json = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    #expect(json["summary"] as? String == "On · lid mode · 20m left")
    #expect((json["effective"] as? [String: Any])?["lid"] as? Bool == true)
    #expect(json["batteryPercent"] as? Int == 64)
    #expect(json["onAC"] as? Bool == false)
    #expect(json["thermal"] as? String == "fair")
    let leases = try #require(json["leases"] as? [[String: Any]])
    #expect(leases.compactMap { $0["id"] as? String } == ["mcp-claude-desktop-500-1"])
    #expect(leases.first?["level"] as? String == "lid")
    #expect(leases.first?["expiresAt"] is String)
    #expect(harness.toolResult(2)?["structuredContent"] is [String: Any])
}

@Test func clientNamedTerminalListsItsOwnLease() async throws {
    // The app files a client calling itself "Terminal" as "MCP client"; the server must agree.
    let lease = leaseInfo(id: "mcp-mcp-client-500-1", owner: OwnerInfo(kind: "mcp", name: "MCP client"),
                          watchPid: MCPHarness.defaultPID)
    var harness = MCPHarness()
    harness.client = ScriptedClient { request in
        guard request.op == .status else { return .success(plausibleReply(to: request)) }
        return .success(.success(id: request.id, .status(statusResult(leases: [lease]))))
    }
    _ = await harness.run([initialize("terminal"), call(2, "keep_awake", #"{"minutes":5}"#), call(3, "awake_status")])
    let args = acquireArgs(of: harness.client.requests.first)
    #expect(args?.id == "mcp-mcp-client-500-1")
    #expect(args?.reason == "Requested by MCP client")
    let text = try #require(harness.text(3))
    let json = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    #expect((json["leases"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == ["mcp-mcp-client-500-1"])
}

// MARK: - notify

@Test func notifySendsClientName() async throws {
    let harness = MCPHarness()
    _ = await harness.run([
        initialize("cursor-vscode"), call(2, "notify", #"{"title":"Done","body":"Build finished"}"#), call(3, "notify", #"{"body":"x"}"#)
    ])
    let request = try #require(harness.client.requests.first)
    #expect(request.op == .notify)
    #expect(request.args == .notify(NotifyArgs(title: "Done", body: "Build finished", client: "cursor-vscode")))
    #expect(harness.isError(2) == false)
    #expect(harness.isError(3) == true)
    #expect(harness.client.requests.count == 1)
}

@Test func notifyBeforeInitializeIsAnMCPClient() async throws {
    let harness = MCPHarness()
    _ = await harness.run([call(1, "notify", #"{"title":"Done"}"#)])
    let request = try #require(harness.client.requests.first)
    #expect(request.args == .notify(NotifyArgs(title: "Done", body: nil, client: "")))
}

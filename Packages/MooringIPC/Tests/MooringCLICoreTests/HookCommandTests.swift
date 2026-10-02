import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

private let fixtureNames = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PreToolUse-internalAgent", "PermissionRequest", "Notification",
    "PostToolUse", "PostToolBatch", "SubagentStart", "SubagentStop", "Stop", "Stop-withBackgroundTask", "SessionEnd"
]

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/hooks"))
    return try Data(contentsOf: url)
}

/// The event a fixture is for: its file name up to any `-` suffix.
private func event(of name: String) -> String {
    String(name.split(separator: "-").first ?? "")
}

private let sessionID = "00000000-0000-0000-0000-000000000001"

/// A shell under `claude`, as the hook script's parent chain looks.
private let claudeTable = FakeProcessTable([proc(100, 90, "sh"), proc(90, 1, "claude")])

private func hookArgs(_ harness: Harness) throws -> HookArgs {
    let request = try #require(harness.hookClient.requests.first)
    #expect(request.op == .hook)
    guard case .hook(let args) = request.args else {
        Issue.record("not a hook request")
        throw CLIError.usage("not a hook request")
    }
    return args
}

private func expectSilent(_ harness: Harness, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(harness.capture.stdout.isEmpty, sourceLocation: sourceLocation)
    #expect(harness.capture.stderr.isEmpty, sourceLocation: sourceLocation)
}

@Test(arguments: fixtureNames)
func everyFixtureSendsOneHookRequest(name: String) async throws {
    let harness = Harness(table: claudeTable, input: try fixture(name))
    #expect(await harness.run(["hook", event(of: name)]) == 0)

    #expect(harness.hookClient.requests.count == 1)
    #expect(harness.client.requests.isEmpty)
    let args = try hookArgs(harness)
    #expect(args.event == event(of: name))
    #expect(args.sessionId == sessionID)
    #expect(args.cwd == "/Users/test/project")
    #expect(args.watchPid == 90)
    expectSilent(harness)
}

@Test func autoWatchSkipsTheHookScriptShell() async throws {
    // mooring runs as a child of the script's `sh`, which sits under the hook's own `sh`, under claude.
    let table = FakeProcessTable([proc(200, 100, "sh"), proc(100, 90, "sh"), proc(90, 1, "claude")])
    let harness = Harness(table: table, parentPID: 200, input: try fixture("Stop"))
    #expect(await harness.run(["hook", "Stop"]) == 0)
    #expect(try hookArgs(harness).watchPid == 90)
}

@Test func fieldsComeFromTheRightKeys() async throws {
    let notification = Harness(table: claudeTable, input: try fixture("Notification"))
    _ = await notification.run(["hook", "Notification"])
    #expect(try hookArgs(notification).notificationType == "permission_prompt")
    #expect(try hookArgs(notification).agentID == nil)

    let subagent = Harness(table: claudeTable, input: try fixture("SubagentStart"))
    _ = await subagent.run(["hook", "SubagentStart"])
    #expect(try hookArgs(subagent).agentID == "a1d0a20d24960c95b")
    #expect(try hookArgs(subagent).agentType == "general-purpose")

    let internalAgent = Harness(table: claudeTable, input: try fixture("PreToolUse-internalAgent"))
    _ = await internalAgent.run(["hook", "PreToolUse"])
    #expect(try hookArgs(internalAgent).agentID == "a2117a4ce6fcb3846")
    #expect(try hookArgs(internalAgent).agentType?.isEmpty ?? true)
}

@Test func runningBackgroundTasksAreCounted() async throws {
    let withTask = Harness(table: claudeTable, input: try fixture("Stop-withBackgroundTask"))
    _ = await withTask.run(["hook", "Stop"])
    #expect(try hookArgs(withTask).runningBackgroundTasks == 1)

    let empty = Harness(table: claudeTable, input: try fixture("Stop"))
    _ = await empty.run(["hook", "Stop"])
    #expect(try hookArgs(empty).runningBackgroundTasks == 0)

    let absent = Harness(table: claudeTable, input: try fixture("PreToolUse"))
    _ = await absent.run(["hook", "PreToolUse"])
    #expect(try hookArgs(absent).runningBackgroundTasks == nil)

    let mixed = Data(#"""
    {"session_id": "s", "background_tasks": [{"status": "running"}, {"status": "completed"}, {"status": "running"}, {}]}
    """#.utf8)
    let counted = Harness(table: claudeTable, input: mixed)
    _ = await counted.run(["hook", "Stop"])
    #expect(try hookArgs(counted).runningBackgroundTasks == 2)
}

@Test func eventNameComesFromTheArgumentNotThePayload() async throws {
    let harness = Harness(table: claudeTable, input: try fixture("Stop"))
    _ = await harness.run(["hook", "SessionEnd"])
    #expect(try hookArgs(harness).event == "SessionEnd")
}

@Test func watchPidIsNilWithoutAWatchableParent() async throws {
    let harness = Harness(table: FakeProcessTable([]), input: try fixture("Stop"))
    #expect(await harness.run(["hook", "Stop"]) == 0)
    #expect(try hookArgs(harness).watchPid == nil)
}

@Test func stdoutAndStderrStayEmpty() async throws {
    let good = try fixture("Stop")
    struct Case {
        let label: String
        let harness: Harness
        let arguments: [String]

        init(_ label: String, _ harness: Harness, _ arguments: [String]) {
            self.label = label
            self.harness = harness
            self.arguments = arguments
        }
    }
    let cases = [
        Case("success", Harness(table: claudeTable, input: good), ["hook", "Stop"]),
        Case("unreachable", Harness(hookClient: RecordingClient(reply: .failure(.unreachable)), input: good), ["hook", "Stop"]),
        Case("noAnswer", Harness(hookClient: RecordingClient(reply: .failure(.noAnswer)), input: good), ["hook", "Stop"]),
        Case("blocked", Harness(hookClient: RecordingClient(reply: .failure(.blocked)), input: good), ["hook", "Stop"]),
        Case("usage", Harness(hookClient: RecordingClient(reply: .failure(.usage("x"))), input: good), ["hook", "Stop"]),
        Case(
            "error reply",
            Harness(
                hookClient: RecordingClient(reply: .success(.failure(id: "r", .internal, "boom"))), input: good
            ),
            ["hook", "Stop"]
        ),
        Case("bad json", Harness(input: Data("{nope".utf8)), ["hook", "Stop"]),
        Case("not an object", Harness(input: Data("[1, 2]".utf8)), ["hook", "Stop"]),
        Case("empty input", Harness(input: Data()), ["hook", "Stop"]),
        Case("missing session", Harness(input: Data(#"{"cwd": "/x"}"#.utf8)), ["hook", "Stop"]),
        Case("missing event", Harness(input: good), ["hook"]),
        Case("json flag", Harness(input: good), ["hook", "Stop", "--json"]),
        Case("no-launch flag", Harness(input: good), ["hook", "Stop", "--no-launch"]),
        Case("extra argument", Harness(input: good), ["hook", "Stop", "extra"])
    ]
    for item in cases {
        #expect(await item.harness.run(item.arguments) == 0, "\(item.label)")
        #expect(item.harness.capture.stdout.isEmpty, "\(item.label)")
        #expect(item.harness.capture.stderr.isEmpty, "\(item.label)")
    }
}

@Test func unreachableAppIsSilentExit0() async throws {
    let harness = Harness(hookClient: RecordingClient(reply: .failure(.unreachable)), input: try fixture("Stop"))
    #expect(await harness.run(["hook", "Stop"]) == 0)
    #expect(harness.hookClient.requests.count == 1)
    expectSilent(harness)
}

@Test func blockedSocketIsSilentExit0() async throws {
    let harness = Harness(hookClient: RecordingClient(reply: .failure(.blocked)), input: try fixture("Stop"))
    #expect(await harness.run(["hook", "Stop"]) == 0)
    expectSilent(harness)
}

@Test func badJSONIsSilentExit0AndSendsNothing() async {
    for text in ["{nope", "", "null", "42", "[]", "\"session_id\""] {
        let harness = Harness(input: Data(text.utf8))
        #expect(await harness.run(["hook", "Stop"]) == 0, "\(text)")
        #expect(harness.hookClient.requests.isEmpty, "\(text)")
        expectSilent(harness)
    }
}

@Test func missingSessionIdSendsNothing() async {
    for text in [#"{"cwd": "/x"}"#, #"{"session_id": ""}"#, #"{"session_id": 7}"#, #"{"session_id": null}"#] {
        let harness = Harness(input: Data(text.utf8))
        #expect(await harness.run(["hook", "Stop"]) == 0, "\(text)")
        #expect(harness.hookClient.requests.isEmpty, "\(text)")
        expectSilent(harness)
    }
}

@Test func oversizeInputIsSilentExit0() async {
    // A valid payload padded past 1 MiB, so a command that stopped reading at 1 MiB would still see valid JSON.
    var input = Data(#"{"session_id": "s"}"#.utf8)
    input.append(Data(repeating: UInt8(ascii: " "), count: 1_048_576 + 1 - input.count))
    #expect(input.count == 1_048_576 + 1)
    let harness = Harness(input: input)
    #expect(await harness.run(["hook", "Stop"]) == 0)
    #expect(harness.hookClient.requests.isEmpty)
    expectSilent(harness)
}

@Test func inputOfExactlyOneMiBIsAccepted() async {
    var input = Data(#"{"session_id": "s"}"#.utf8)
    input.append(Data(repeating: UInt8(ascii: " "), count: 1_048_576 - input.count))
    let harness = Harness(input: input)
    #expect(await harness.run(["hook", "Stop"]) == 0)
    #expect(harness.hookClient.requests.count == 1)
}

@Test func neverLaunches() async throws {
    let harness = Harness(table: claudeTable, input: try fixture("SessionStart"))
    #expect(await harness.run(["hook", "SessionStart"]) == 0)
    #expect(harness.hookClient.lastLaunch == false)
}

@Test func hookIsHiddenFromHelp() async {
    let harness = Harness()
    #expect(await harness.run(["--help"]) == 0)
    #expect(!harness.capture.stdout.contains("hook"))
    #expect(harness.capture.stdout.contains("doctor"))
}

// MARK: - Real sockets

private let hookReply = Response.success(id: "req-1", .hook(HookResult(action: "renew")))

/// A CLI environment whose hook goes through a real `SocketClient` and whose stdin holds `input`.
private func socketEnvironment(path: String, replyTimeout: TimeInterval, input: Data, capture: Capture) -> CLIEnvironment {
    CLIEnvironment(
        client: RecordingClient(), processes: claudeTable, ownPID: 500, parentPID: 100,
        write: { capture.writeOut($0) }, writeError: { capture.writeErr($0) },
        newID: { "req-1" }, now: { fixedNow }, ownBinaryPath: "/nowhere/mooring", pathEnv: nil,
        readInput: { Data(input.prefix($0)) },
        hookClient: SocketClient(path: path, replyTimeout: replyTimeout, launchWait: 0, launcher: {}), claude: { nil }
    )
}

@Test func silentAppGivesUpWithin2s() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let server = LineServer(path: folder + "/s.sock", reply: nil)
    try server.start()
    defer { server.stop() }

    let capture = Capture()
    let environment = socketEnvironment(path: server.path, replyTimeout: 1.5, input: try fixture("Stop"), capture: capture)
    let started = ContinuousClock.now
    #expect(await MooringCLI.run(["hook", "Stop"], environment: environment) == 0)
    #expect(ContinuousClock.now - started < .seconds(2))
    #expect(server.requests.count == 1)
    #expect(capture.stdout.isEmpty)
    #expect(capture.stderr.isEmpty)
}

@Test func hookRoundTripIsFast() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let server = LineServer(path: folder + "/s.sock", reply: try WireCoding.encodeLine(hookReply))
    try server.start()
    defer { server.stop() }

    let capture = Capture()
    let environment = socketEnvironment(path: server.path, replyTimeout: 1.5, input: try fixture("Stop"), capture: capture)
    var durations: [Double] = []
    for _ in 0..<5 {
        let started = ContinuousClock.now
        #expect(await MooringCLI.run(["hook", "Stop"], environment: environment) == 0)
        let elapsed = ContinuousClock.now - started
        durations.append(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }
    let median = durations.sorted()[2]
    print("hook round trip median: \(Int(median * 1000)) ms (runs: \(durations.map { Int($0 * 1000) }))")
    // Locally this is well under 50 ms; the looser bound is for slow CI machines.
    #expect(median < 0.15)
    #expect(server.requests.count == 5)
    #expect(capture.stdout.isEmpty)
    #expect(capture.stderr.isEmpty)
}

import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

private func acquireArgs(_ request: Request?) -> AcquireArgs? {
    if case .acquire(let args)? = request?.args { return args }
    return nil
}

@Test func onBuildsAnAcquire() async {
    let harness = Harness()
    let code = await harness.run(["on", "--level", "lid", "--for", "30m", "--reason", "build"])
    #expect(code == 0)
    #expect(harness.lidClient.lastRequest == Request(
        v: 1, id: "req-1", op: .acquire,
        args: .acquire(AcquireArgs(kind: .on, id: nil, level: "lid", ttl: 1800, watchPid: nil, reason: "build", agent: nil))
    ))
}

@Test func levelIsSentInCanonicalForm() async {
    let harness = Harness()
    _ = await harness.run(["on", "--level", "lid,display"])
    #expect(acquireArgs(harness.lidClient.lastRequest)?.level == "display,lid")
}

@Test func badDurationIsUsageExit1() async {
    let harness = Harness()
    #expect(await harness.run(["on", "--for", "5"]) == 1)
    #expect(harness.client.requests.isEmpty)
    #expect(!harness.capture.stderr.isEmpty)
}

@Test func badLevelIsUsageExit1() async {
    let harness = Harness()
    #expect(await harness.run(["on", "--level", "turbo"]) == 1)
    #expect(await harness.run(["anchor", "--pid", "5", "--level", "turbo"]) == 1)
    #expect(await harness.run(["lease", "acquire", "job", "--ttl", "5m", "--level", "turbo"]) == 1)
    #expect(harness.client.requests.isEmpty)
}

@Test func unknownCommandAndFlagAreUsageErrors() async {
    let harness = Harness()
    #expect(await harness.run(["frobnicate"]) == 1)
    #expect(await harness.run(["status", "--bogus"]) == 1)
    #expect(harness.client.requests.isEmpty)
}

@Test func leaseAcquireWithAutoWatch() async {
    let table = FakeProcessTable([proc(100, 90, "zsh"), proc(90, 80, "zsh"), proc(80, 1, "claude"), proc(1, 0, "launchd")])
    let harness = Harness(table: table)
    let code = await harness.run(["lease", "acquire", "job", "--watch-pid", "auto", "--reason", "tests"])
    #expect(code == 0)
    let args = acquireArgs(harness.client.lastRequest)
    #expect(args?.kind == .lease)
    #expect(args?.id == "job")
    #expect(args?.watchPid == 80)
    #expect(args?.agent == "Claude Code")
    #expect(args?.reason == "tests")
}

@Test func autoSkipsLoginAndShells() async {
    let table = FakeProcessTable([proc(100, 90, "zsh"), proc(90, 70, "login"), proc(70, 1, "Terminal")])
    let harness = Harness(table: table)
    #expect(await harness.run(["lease", "acquire", "job", "--watch-pid", "auto"]) == 0)
    let args = acquireArgs(harness.client.lastRequest)
    #expect(args?.watchPid == 70)
    #expect(args?.agent == "Terminal")
}

@Test func autoWithOnlyShellsIsUsageError() async {
    let table = FakeProcessTable([proc(100, 90, "zsh"), proc(90, 1, "bash"), proc(1, 0, "launchd")])
    let harness = Harness(table: table)
    #expect(await harness.run(["lease", "acquire", "job", "--watch-pid", "auto"]) == 1)
    #expect(harness.capture.stderr.contains("Couldn't find a process to watch"))
    #expect(harness.client.requests.isEmpty)
}

@Test func explicitAgentWins() async {
    let table = FakeProcessTable([proc(100, 80, "zsh"), proc(80, 1, "claude")])
    let harness = Harness(table: table)
    #expect(await harness.run(["lease", "acquire", "job", "--watch-pid", "auto", "--agent", "Nightly"]) == 0)
    #expect(acquireArgs(harness.client.lastRequest)?.agent == "Nightly")
}

@Test func explicitWatchPidIsSentAsGiven() async {
    let harness = Harness()
    #expect(await harness.run(["lease", "acquire", "job", "--watch-pid", "4242", "--ttl", "1h"]) == 0)
    let args = acquireArgs(harness.client.lastRequest)
    #expect(args?.watchPid == 4242)
    #expect(args?.ttl == 3600)
    #expect(args?.agent == nil)
}

@Test func badWatchPidIsUsageError() async {
    let harness = Harness()
    for value in ["soon", "0", "-4", "12x"] {
        #expect(await harness.run(["lease", "acquire", "job", "--watch-pid", value]) == 1)
    }
    #expect(harness.client.requests.isEmpty)
}

@Test func leaseRenewSendsTheTTL() async {
    let harness = Harness()
    harness.client.reply(with: .success(id: "r", .renew(leaseInfo(expiresAt: fixedNow.addingTimeInterval(600)))))
    #expect(await harness.run(["lease", "renew", "job", "--ttl", "10m"]) == 0)
    #expect(harness.client.lastRequest?.args == .renew(RenewArgs(id: "job", ttl: 600)))
    #expect(await harness.run(["lease", "renew", "job"]) == 0)
    #expect(harness.client.lastRequest?.args == .renew(RenewArgs(id: "job", ttl: nil)))
}

@Test func releaseWithAfter() async {
    let harness = Harness()
    #expect(await harness.run(["lease", "release", "job", "--after", "2m"]) == 0)
    #expect(harness.client.lastRequest?.args == .release(ReleaseArgs(kind: .lease, id: "job", after: 120)))
}

@Test func offSendsReleaseOff() async {
    let harness = Harness()
    #expect(await harness.run(["off"]) == 0)
    #expect(harness.client.lastRequest?.op == .release)
    #expect(harness.client.lastRequest?.args == .release(ReleaseArgs(kind: .off, id: nil, after: nil)))
}

@Test func anchorWithPid() async {
    let harness = Harness()
    #expect(await harness.run(["anchor", "--pid", "321", "--level", "display", "--reason", "render", "--agent", "Make"]) == 0)
    #expect(acquireArgs(harness.client.lastRequest) == AcquireArgs(
        kind: .anchor, id: nil, level: "display", ttl: nil, watchPid: 321, reason: "render", agent: "Make"
    ))
}

@Test func anchorNeedsAPidOrACommand() async {
    let harness = Harness()
    #expect(await harness.run(["anchor"]) == 1)
    #expect(harness.capture.stderr.contains("Give --pid <pid> or -- <command>"))
    #expect(await harness.run(["anchor", "--pid", "0"]) == 1)
    #expect(harness.client.requests.isEmpty)
}

@Test func errorResponsesMapExitCodes() async {
    let cases: [(ErrorCode, Int32)] = [(.denied, 2), (.guardrail, 2), (.notFound, 1), (.badRequest, 1), (.internal, 4)]
    for (code, expected) in cases {
        let harness = Harness(client: RecordingClient(reply: .success(.failure(id: "r", code, "nope \(code.rawValue)"))))
        #expect(await harness.run(["status"]) == expected)
        #expect(harness.capture.stderr == "mooring: nope \(code.rawValue)\n")
        #expect(harness.capture.stdout.isEmpty)
    }
}

@Test func unreachableExits3WithMessage() async {
    let harness = Harness(client: RecordingClient(reply: .failure(.unreachable)))
    #expect(await harness.run(["status"]) == 3)
    #expect(harness.capture.stderr == "mooring: Mooring isn't running and couldn't be started\n")
    #expect(harness.capture.stdout.isEmpty)
}

@Test func unreachableWithJSONPrintsTheErrorObject() async throws {
    let harness = Harness(client: RecordingClient(reply: .failure(.unreachable)))
    #expect(await harness.run(["status", "--json"]) == 3)
    #expect(harness.capture.stdout
        == #"{"ok":false,"error":{"code":"unreachable","message":"Mooring isn't running and couldn't be started"}}"# + "\n")
    #expect(harness.capture.stderr.isEmpty)
}

@Test func noAnswerPrintsDidntAnswer() async {
    let message = "Mooring didn't answer. It may be busy; the request may have gone through, so check `mooring status`."
    let human = Harness(client: RecordingClient(reply: .failure(.noAnswer)))
    #expect(await human.run(["status"]) == 3)
    #expect(human.capture.stderr == "mooring: \(message)\n")
    #expect(human.capture.stdout.isEmpty)

    let json = Harness(client: RecordingClient(reply: .failure(.noAnswer)))
    #expect(await json.run(["status", "--json"]) == 3)
    #expect(json.capture.stdout == #"{"ok":false,"error":{"code":"unreachable","message":"\#(message)"}}"# + "\n")
    #expect(json.capture.stderr.isEmpty)
}

@Test func busyPrintsTryAgain() async {
    let message = "Mooring is running but didn't answer. Try again in a moment."
    let human = Harness(client: RecordingClient(reply: .failure(.busy)))
    #expect(await human.run(["status"]) == 3)
    #expect(human.capture.stderr == "mooring: \(message)\n")

    let json = Harness(client: RecordingClient(reply: .failure(.busy)))
    #expect(await json.run(["status", "--json"]) == 3)
    #expect(json.capture.stdout == #"{"ok":false,"error":{"code":"unreachable","message":"\#(message)"}}"# + "\n")
}

@Test func blockedPrintsPermissionDenied() async {
    let message = "Can't reach Mooring's socket (permission denied). "
        + "If this runs in a sandbox, allow ~/Library/Application Support/Mooring/mooring.sock"
    let human = Harness(client: RecordingClient(reply: .failure(.blocked)))
    #expect(await human.run(["status"]) == 3)
    #expect(human.capture.stderr == "mooring: \(message)\n")
    #expect(human.capture.stdout.isEmpty)

    let json = Harness(client: RecordingClient(reply: .failure(.blocked)))
    #expect(await json.run(["status", "--json"]) == 3)
    #expect(json.capture.stdout == #"{"ok":false,"error":{"code":"unreachable","message":"\#(message)"}}"# + "\n")
    #expect(json.capture.stderr.isEmpty)
}

private func usageObject(_ message: String) -> String {
    #"{"ok":false,"error":{"code":"usage","message":"\#(message)"}}"# + "\n"
}

@Test func jsonBadDurationIsAUsageObject() async {
    let harness = Harness()
    #expect(await harness.run(["on", "--for", "5", "--json"]) == 1)
    #expect(harness.capture.stdout == usageObject("Invalid duration '5' for --for. Use forms like 90s, 15m, 2h or 1h30m"))
    #expect(harness.capture.stderr.isEmpty)
    #expect(harness.client.requests.isEmpty)
}

@Test func jsonParseErrorsAreUsageObjects() async {
    let cases: [([String], String)] = [
        (["status", "--bogus", "--json"], "Unknown option '--bogus'"),
        (["--json", "status", "--bogus"], ""),
        (["lease", "acquire", "--json"], "Missing expected argument '<id>'"),
        (["lease", "acquire", "job", "--watch-pid", "x\"y", "--json"], "--watch-pid takes auto or a process id, not 'x\"y'"),
        (["--json", "frobnicate"], "")
    ]
    for (arguments, message) in cases {
        let harness = Harness()
        #expect(await harness.run(arguments) == 1)
        let lines = harness.capture.stdout.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 2 && lines[1].isEmpty, "\(arguments)")
        #expect(lines.first?.hasPrefix(#"{"ok":false,"error":{"code":"usage","message":""#) == true, "\(arguments)")
        #expect(message.isEmpty || harness.capture.stdout.contains(message.replacingOccurrences(of: "\"", with: "\\\"")), "\(arguments)")
        #expect(harness.capture.stderr.isEmpty)
    }
}

@Test func jsonAutoWatchFailureIsAUsageObject() async {
    let table = FakeProcessTable([proc(100, 90, "zsh"), proc(90, 1, "bash"), proc(1, 0, "launchd")])
    let harness = Harness(table: table)
    #expect(await harness.run(["lease", "acquire", "job", "--watch-pid", "auto", "--json"]) == 1)
    #expect(harness.capture.stdout == usageObject("Couldn't find a process to watch"))
    #expect(harness.capture.stderr.isEmpty)
    #expect(harness.client.requests.isEmpty)
}

@Test func jsonAnchorUsageErrorsAreUsageObjects() async {
    let harness = Harness()
    #expect(await harness.run(["anchor", "--json"]) == 1)
    #expect(harness.capture.stdout == usageObject("Give --pid <pid> or -- <command>"))
    #expect(await harness.run(["anchor", "--pid", "4", "--json", "--", "sleep", "1"]) == 1)
    #expect(harness.capture.stdout.hasSuffix(usageObject("Use either --pid or -- <command>")))
    #expect(harness.capture.stderr.isEmpty)
    #expect(harness.client.requests.isEmpty)
}

@Test func jsonHelpAndVersionAreUnchanged() async {
    let harness = Harness()
    #expect(await harness.run(["--version", "--json"]) == 0)
    #expect(harness.capture.stdout == "mooring 9.9.9-test\n")
    #expect(await harness.run(["status", "--help", "--json"]) == 0)
    #expect(harness.capture.stdout.contains("USAGE: mooring status"))
    #expect(harness.capture.stderr.isEmpty)
}

@Test func humanUsageErrorsUnchanged() async {
    let parse = Harness()
    #expect(await parse.run(["on", "--for", "5"]) == 1)
    #expect(parse.capture.stdout.isEmpty)
    #expect(parse.capture.stderr == """
    Error: Invalid duration '5' for --for. Use forms like 90s, 15m, 2h or 1h30m
    Usage: mooring on [--level <level>] [--for <for>] [--reason <reason>] [--json] [--no-launch]
      See 'mooring on --help' for more information.

    """)

    let table = FakeProcessTable([proc(100, 90, "zsh"), proc(90, 1, "bash"), proc(1, 0, "launchd")])
    let execute = Harness(table: table)
    #expect(await execute.run(["lease", "acquire", "job", "--watch-pid", "auto"]) == 1)
    #expect(execute.capture.stdout.isEmpty)
    #expect(execute.capture.stderr == "mooring: Couldn't find a process to watch\n")
}

@Test func noLaunchFlagIsPassedThrough() async {
    let harness = Harness()
    _ = await harness.run(["status", "--no-launch"])
    #expect(harness.client.lastLaunch == false)
    _ = await harness.run(["status"])
    #expect(harness.client.lastLaunch == true)
}

@Test func versionAndHelpExitZero() async {
    let harness = Harness()
    #expect(await harness.run(["--version"]) == 0)
    // The version is the environment's, which the binary reads from its enclosing app.
    #expect(harness.capture.stdout == "mooring 9.9.9-test\n")
    #expect(await harness.run(["lease", "acquire", "--help"]) == 0)
    #expect(harness.client.requests.isEmpty)
}

@Test func helpHasForAgentsSection() async {
    let harness = Harness()
    #expect(await harness.run(["--help"]) == 0)
    let text = harness.capture.stdout
    #expect(text.contains("Keep your Mac awake from scripts and agents"))
    #expect(text.contains("For agents"))
    #expect(text.contains(#"mooring lease acquire <name> --watch-pid auto --reason "…""#))
    #expect(text.contains("mooring lease release <name>"))
    #expect(text.contains("mooring anchor -- <command>"))
}

@Test func helpMentionsWin() async throws {
    let harness = Harness()
    #expect(await harness.run(["--help"]) == 0)
    let text = harness.capture.stdout
    let forAgents = try #require(text.range(of: "For agents"))
    #expect(text[forAgents.upperBound...].contains("mooring win"))
}

@Test func bareMooringPrintsHelp() async {
    let harness = Harness()
    #expect(await harness.run([]) == 0)
    #expect(harness.capture.stdout.contains("USAGE: mooring"))
    #expect(harness.client.requests.isEmpty)
}

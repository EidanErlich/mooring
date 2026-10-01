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
    #expect(harness.client.lastRequest == Request(
        v: 1, id: "req-1", op: .acquire,
        args: .acquire(AcquireArgs(kind: .on, id: nil, level: "lid", ttl: 1800, watchPid: nil, reason: "build", agent: nil))
    ))
}

@Test func levelIsSentInCanonicalForm() async {
    let harness = Harness()
    _ = await harness.run(["on", "--level", "lid,display"])
    #expect(acquireArgs(harness.client.lastRequest)?.level == "display,lid")
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
    #expect(harness.capture.stdout == "mooring 0.2.0-dev\n")
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

@Test func bareMooringPrintsHelp() async {
    let harness = Harness()
    #expect(await harness.run([]) == 0)
    #expect(harness.capture.stdout.contains("USAGE: mooring"))
    #expect(harness.client.requests.isEmpty)
}

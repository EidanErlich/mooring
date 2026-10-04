import Darwin
import MooringIPC
import Testing
@testable import MooringCLICore

@Test func systemTableFindsThisProcess() throws {
    let entry = try #require(SystemProcessTable().entry(getpid()))
    #expect(entry.parent == getppid())
    #expect(!entry.name.isEmpty)
}

@Test func systemTableReturnsNilForAMissingProcess() {
    #expect(SystemProcessTable().entry(Int32.max) == nil)
    #expect(SystemProcessTable().arguments(Int32.max) == nil)
}

@Test func systemTableReadsThisProcessesArguments() throws {
    let arguments = try #require(SystemProcessTable().arguments(getpid()))
    #expect(arguments == CommandLine.arguments)
}

@Test func walkStopsAtTheFirstNonShell() {
    let table = FakeProcessTable([proc(100, 90, "zsh"), proc(90, 80, "-zsh"), proc(80, 1, "claude"), proc(1, 0, "launchd")])
    #expect(ProcessTree.autoWatch(from: 100, in: table)?.pid == 80)
}

@Test func walkReturnsNilAtLaunchd() {
    let table = FakeProcessTable([proc(100, 90, "zsh"), proc(90, 1, "bash"), proc(1, 0, "launchd")])
    #expect(ProcessTree.autoWatch(from: 100, in: table) == nil)
}

@Test func walkReturnsNilForAnUnknownProcess() {
    #expect(ProcessTree.autoWatch(from: 100, in: FakeProcessTable([])) == nil)
}

@Test func walkSurvivesALoop() {
    let table = FakeProcessTable([proc(100, 90, "zsh"), proc(90, 100, "sh")])
    #expect(ProcessTree.autoWatch(from: 100, in: table) == nil)
}

@Test func agentNames() {
    #expect(ProcessTree.agentName(for: "claude") == "Claude Code")
    #expect(ProcessTree.agentName(for: "codex") == "Codex")
    #expect(ProcessTree.agentName(for: "Terminal") == "Terminal")
    // The desktop apps aren't the CLIs.
    #expect(ProcessTree.agentName(for: "Claude") == "Claude")
    #expect(ProcessTree.agentName(for: "-claude") == "Claude Code")
}

@Test func npmClaudeCountsAsClaude() async {
    // Claude Code installed with npm runs as `node`, its script the first argument.
    let rows = [proc(100, 90, "zsh"), proc(90, 80, "-zsh"), proc(80, 1, "node"), proc(1, 0, "launchd")]
    let table = FakeProcessTable(rows, arguments: [80: ["node", "/Users/me/.npm-global/bin/claude"]])
    let watched = ProcessTree.autoWatch(from: 100, in: table)
    #expect(watched == proc(80, 1, "claude"))
    #expect(ProcessTree.agentName(for: proc(80, 1, "node"), in: table) == "Claude Code")

    let harness = Harness(table: table)
    #expect(await harness.run(["lease", "acquire", "job", "--watch-pid", "auto"]) == 0)
    let args = acquireArgs(of: harness.client.lastRequest)
    #expect(args?.watchPid == 80)
    #expect(args?.agent == "Claude Code")

    // Any other node program keeps its own name.
    let vite = FakeProcessTable(rows, arguments: [80: ["node", "/usr/local/bin/vite"]])
    #expect(ProcessTree.autoWatch(from: 100, in: vite)?.name == "node")
    #expect(ProcessTree.agentName(for: proc(80, 1, "node"), in: vite) == "node")
}

@Test func watchedNpmClaudeIsNamed() async {
    let reply = acquired(leaseInfo(id: "anchor-80", watchPid: 80))
    let script = "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"
    let table = FakeProcessTable([proc(80, 1, "node")], arguments: [80: ["node", script]])
    let harness = Harness(client: RecordingClient(reply: .success(reply)), table: table)
    #expect(await harness.run(["anchor", "--pid", "80"]) == 0)
    #expect(harness.capture.stdout == "Anchored anchor-80 · while Claude Code (80) runs\n")
}

@Test func autoWatchFindsTitledNpmClaude() {
    // A titled npm Claude Code: node, with argv overwritten by its process title.
    let table = FakeProcessTable(
        [proc(100, 90, "zsh"), proc(90, 1, "node")], arguments: [90: ["claude", "", ""]]
    )
    let entry = ProcessTree.autoWatch(from: 100, in: table)
    #expect(entry?.pid == 90)
    #expect(entry?.name == "claude")
    #expect(entry.map { ProcessTree.agentName(for: $0, in: table) } == "Claude Code")
}

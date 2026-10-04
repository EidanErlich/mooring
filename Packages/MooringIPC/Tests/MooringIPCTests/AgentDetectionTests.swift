import MooringIPC
import Testing

private func proc(_ pid: Int32, _ parent: Int32, _ name: String) -> ProcessEntry {
    ProcessEntry(pid: pid, parent: parent, name: name)
}

private struct FakeTable: ProcessTable {
    let entries: [Int32: ProcessEntry]
    let commandLines: [Int32: [String]]

    init(_ rows: [ProcessEntry], arguments: [Int32: [String]] = [:]) {
        entries = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
        commandLines = arguments
    }

    func entry(_ pid: Int32) -> ProcessEntry? { entries[pid] }
    func arguments(_ pid: Int32) -> [String]? { commandLines[pid] }
}

@Test func zshThenClaudeIsClaudeCode() {
    let table = FakeTable([proc(100, 90, "zsh"), proc(90, 80, "node"), proc(80, 1, "claude"), proc(1, 0, "launchd")])
    #expect(AgentDetection.agent(for: 100, in: table) == "Claude Code")
}

@Test func loginThenTerminalIsAPerson() {
    let table = FakeTable([proc(100, 90, "-zsh"), proc(90, 70, "login"), proc(70, 1, "Terminal"), proc(1, 0, "launchd")])
    #expect(AgentDetection.agent(for: 100, in: table) == nil)
}

@Test func codexIsDetected() {
    let table = FakeTable([proc(100, 90, "sh"), proc(90, 1, "codex")])
    #expect(AgentDetection.agent(for: 100, in: table) == "Codex")
}

@Test func desktopClaudeAppIsAPerson() {
    // The Claude desktop app's terminal panel: a person typing, not Claude Code.
    let table = FakeTable([proc(100, 90, "zsh"), proc(90, 80, "Claude Helper"), proc(80, 1, "Claude")])
    #expect(AgentDetection.agent(for: 100, in: table) == nil)
}

@Test func claudeCodeCLIIsAnAgent() {
    let table = FakeTable([proc(100, 90, "zsh"), proc(90, 1, "claude")])
    #expect(AgentDetection.agent(for: 100, in: table) == "Claude Code")
}

@Test func npmClaudeIsAnAgent() {
    // Claude Code installed with npm runs as `node` with its script as the first argument.
    let rows = [proc(100, 90, "zsh"), proc(90, 1, "node")]
    let npmLink = FakeTable(rows, arguments: [90: ["node", "/opt/homebrew/bin/claude", "--resume"]])
    #expect(AgentDetection.agentProcess(for: 100, in: npmLink)?.name == "Claude Code")
    #expect(AgentDetection.agentProcess(for: 100, in: npmLink)?.pid == 90)
    let package = FakeTable(rows, arguments: [90: ["node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"]])
    #expect(AgentDetection.agent(for: 100, in: package) == "Claude Code")
    // Any other node script, a node whose arguments can't be read and a script merely named like Claude are people.
    #expect(AgentDetection.agent(for: 100, in: FakeTable(rows, arguments: [90: ["node", "/usr/local/bin/vite"]])) == nil)
    #expect(AgentDetection.agent(for: 100, in: FakeTable(rows)) == nil)
    #expect(AgentDetection.agent(for: 100, in: FakeTable(rows, arguments: [90: ["node"]])) == nil)
    #expect(AgentDetection.agent(for: 100, in: FakeTable(rows, arguments: [90: ["node", "/srv/claude-notes/app.js"]])) == nil)
    // Only node's script counts: another program run with a Claude path is still itself.
    let python = FakeTable([proc(100, 90, "zsh"), proc(90, 1, "python3")], arguments: [90: ["python3", "/usr/local/bin/claude"]])
    #expect(AgentDetection.agent(for: 100, in: python) == nil)
}

@Test func codexDesktopIsAPerson() {
    let table = FakeTable([proc(100, 90, "zsh"), proc(90, 80, "Codex Helper"), proc(80, 1, "Codex")])
    #expect(AgentDetection.agent(for: 100, in: table) == nil)
}

@Test func pidItselfCanBeTheAgent() {
    let table = FakeTable([proc(100, 1, "-claude")])
    #expect(AgentDetection.agent(for: 100, in: table) == "Claude Code")
}

@Test func loopStopsAt64Steps() {
    // A cycle with no agent in it must end rather than spin.
    let table = FakeTable([proc(100, 90, "zsh"), proc(90, 100, "sh")])
    #expect(AgentDetection.agent(for: 100, in: table) == nil)
    // The agent sits 70 steps up a chain, past the cap.
    var rows = (100..<170).map { proc($0, $0 + 1, "sh") }
    rows.append(proc(170, 2, "claude"))
    #expect(AgentDetection.agent(for: 100, in: FakeTable(rows)) == nil)
}

@Test func missingPidIsAPerson() {
    #expect(AgentDetection.agent(for: 100, in: FakeTable([])) == nil)
    #expect(AgentDetection.agent(for: 1, in: FakeTable([proc(1, 0, "claude")])) == nil)
}

@Test func agentProcessGivesTheAgentsPid() {
    let table = FakeTable([proc(100, 90, "zsh"), proc(90, 80, "node"), proc(80, 1, "claude")])
    let agent = AgentDetection.agentProcess(for: 100, in: table)
    #expect(agent?.name == "Claude Code")
    #expect(agent?.pid == 80)
    #expect(AgentDetection.agentProcess(for: 100, in: FakeTable([proc(100, 1, "zsh")])) == nil)
}

@Test func descendsWalksUpFromTheWatchedPid() {
    let table = FakeTable([proc(300, 200, "sleep"), proc(200, 80, "mooring"), proc(80, 70, "claude"), proc(70, 1, "zsh")])
    #expect(AgentDetection.descends(300, from: 80, in: table))
    #expect(AgentDetection.descends(80, from: 80, in: table))
    // The agent's own ancestors, launchd and pids missing from the table don't run below it.
    #expect(!AgentDetection.descends(70, from: 80, in: table))
    #expect(!AgentDetection.descends(1, from: 80, in: table))
    #expect(!AgentDetection.descends(4242, from: 80, in: table))
    // A cycle ends rather than spins.
    #expect(!AgentDetection.descends(10, from: 80, in: FakeTable([proc(10, 11, "sh"), proc(11, 10, "sh")])))
}

import MooringIPC
import Testing

private func proc(_ pid: Int32, _ parent: Int32, _ name: String) -> ProcessEntry {
    ProcessEntry(pid: pid, parent: parent, name: name)
}

private struct FakeTable: ProcessTable {
    let entries: [Int32: ProcessEntry]

    init(_ rows: [ProcessEntry]) {
        entries = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
    }

    func entry(_ pid: Int32) -> ProcessEntry? { entries[pid] }
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

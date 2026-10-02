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

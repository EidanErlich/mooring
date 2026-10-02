import Foundation
import Testing
@testable import Mooring

private struct Entry {
    var id: String
    var version: String
    var enabled: Bool
}

private func listJSON(_ plugins: [Entry]) -> Data {
    let items = plugins.map { "{\"id\":\"\($0.id)\",\"version\":\"\($0.version)\",\"enabled\":\($0.enabled),\"scope\":\"user\"}" }
    return Data("[\(items.joined(separator: ","))]".utf8)
}

private func failure(_ result: Result<Void, ClaudePluginInstaller.InstallError>) -> ClaudePluginInstaller.InstallError? {
    if case .failure(let error) = result { return error }
    return nil
}

/// Records every argv and answers from a script, so no real `claude` ever runs.
private final class FakeRunner: ToolRunning, @unchecked Sendable {
    var calls: [[String]] = []
    var results: [ToolResult]

    init(_ results: [ToolResult]) { self.results = results }

    func run(_ argv: [String]) -> ToolResult {
        calls.append(argv)
        return results.isEmpty ? ToolResult(status: 0) : results.removeFirst()
    }
}

struct ClaudePluginInstallerTests {
    @Test func statusClaudeNotFound() {
        #expect(ClaudePluginInstaller.status(listJSON: nil, claudeFound: false, appVersion: "1.0") == .claudeNotFound)
        let json = listJSON([Entry(id: "mooring@mooring-app", version: "1.0", enabled: true)])
        #expect(ClaudePluginInstaller.status(listJSON: json, claudeFound: false, appVersion: "1.0") == .claudeNotFound)
    }

    @Test func statusNotInstalled() {
        #expect(ClaudePluginInstaller.status(listJSON: nil, claudeFound: true, appVersion: "1.0") == .notInstalled)
        #expect(ClaudePluginInstaller.status(listJSON: Data("garbage".utf8), claudeFound: true, appVersion: "1.0") == .notInstalled)
        let other = listJSON([Entry(id: "context7@claude-plugins-official", version: "abc", enabled: true)])
        #expect(ClaudePluginInstaller.status(listJSON: other, claudeFound: true, appVersion: "1.0") == .notInstalled)
    }

    @Test func statusInstalledFromApp() {
        let json = listJSON([Entry(id: "mooring@mooring-app", version: "1.0", enabled: true)])
        #expect(ClaudePluginInstaller.status(listJSON: json, claudeFound: true, appVersion: "1.0")
            == .installedFromApp(version: "1.0"))
    }

    @Test func statusNeedsUpdate() {
        let json = listJSON([Entry(id: "mooring@mooring-app", version: "0.9", enabled: true)])
        #expect(ClaudePluginInstaller.status(listJSON: json, claudeFound: true, appVersion: "1.0")
            == .needsUpdate(installed: "0.9", app: "1.0"))
    }

    @Test func statusInstalledFromGitHub() {
        let json = listJSON([Entry(id: "mooring@mooring", version: "0.5", enabled: true)])
        #expect(ClaudePluginInstaller.status(listJSON: json, claudeFound: true, appVersion: "1.0")
            == .installedFromGitHub(version: "0.5"))
    }

    @Test func statusPrefersAppOverGitHub() {
        let json = listJSON([Entry(id: "mooring@mooring", version: "0.5", enabled: true),
                             Entry(id: "mooring@mooring-app", version: "1.0", enabled: true)])
        #expect(ClaudePluginInstaller.status(listJSON: json, claudeFound: true, appVersion: "1.0")
            == .installedFromApp(version: "1.0"))
    }

    @Test func disabledPluginStillCountsAsInstalled() {
        let json = listJSON([Entry(id: "mooring@mooring-app", version: "1.0", enabled: false)])
        #expect(ClaudePluginInstaller.status(listJSON: json, claudeFound: true, appVersion: "1.0")
            == .installedFromApp(version: "1.0"))
        #expect(ClaudePluginInstaller.isDisabled(listJSON: json))
        #expect(!ClaudePluginInstaller.isDisabled(listJSON: listJSON([Entry(id: "mooring@mooring-app", version: "1.0", enabled: true)])))
        #expect(!ClaudePluginInstaller.isDisabled(listJSON: nil))
        #expect(!ClaudePluginInstaller.isDisabled(listJSON: listJSON([])))
    }

    @Test func statusTextsAndButtons() {
        #expect(ClaudePluginInstaller.Status.installedFromApp(version: "1").text == "Installed (from the app)")
        #expect(ClaudePluginInstaller.Status.installedFromGitHub(version: "1").text == "Installed (from GitHub)")
        #expect(ClaudePluginInstaller.Status.needsUpdate(installed: "1", app: "2").text == "Needs update")
        #expect(ClaudePluginInstaller.Status.notInstalled.text == "Not installed")
        #expect(ClaudePluginInstaller.Status.claudeNotFound.text == "Claude Code not found")
        #expect(ClaudePluginInstaller.Status.notInstalled.buttonTitle == "Install")
        #expect(ClaudePluginInstaller.Status.needsUpdate(installed: "1", app: "2").buttonTitle == "Update")
        #expect(ClaudePluginInstaller.Status.installedFromApp(version: "1").buttonTitle == "Reinstall")
        #expect(ClaudePluginInstaller.Status.installedFromGitHub(version: "1").buttonTitle == nil)
        #expect(ClaudePluginInstaller.Status.claudeNotFound.buttonTitle == nil)
    }

    @Test func installCommandLines() {
        #expect(ClaudePluginInstaller.installCommands(claude: "/x/claude", bundlePlugin: "/App/ClaudePlugin") == [
            ["/x/claude", "plugin", "marketplace", "add", "/App/ClaudePlugin", "-y"],
            ["/x/claude", "plugin", "install", "mooring@mooring-app", "-y"]
        ])
    }

    @Test func findClaudePrefersTheLoginShell() {
        let found = ClaudePluginInstaller.findClaude(loginShellLookup: { "/shell/claude" }, isExecutable: { _ in true })
        #expect(found == "/shell/claude")
    }

    @Test func findClaudeFallsBackToCandidates() {
        let home = NSHomeDirectory()
        let viaHome = ClaudePluginInstaller.findClaude(
            loginShellLookup: { nil }, isExecutable: { $0 == "\(home)/.local/bin/claude" || $0 == "/usr/local/bin/claude" })
        #expect(viaHome == "\(home)/.local/bin/claude")
        let viaLocal = ClaudePluginInstaller.findClaude(loginShellLookup: { nil }, isExecutable: { $0 == "/usr/local/bin/claude" })
        #expect(viaLocal == "/usr/local/bin/claude")
        // A non-absolute lookup result is ignored.
        let ignored = ClaudePluginInstaller.findClaude(
            loginShellLookup: { "claude: aliased" }, isExecutable: { $0 == "/opt/homebrew/bin/claude" })
        #expect(ignored == "/opt/homebrew/bin/claude")
    }

    @Test func findClaudeNone() {
        #expect(ClaudePluginInstaller.findClaude(loginShellLookup: { nil }, isExecutable: { _ in false }) == nil)
    }

    @Test func installEnsuresTheCLIFirstThenRunsBothCommands() {
        var order: [String] = []
        let runner = FakeRunner([ToolResult(status: 0), ToolResult(status: 0)])
        let result = ClaudePluginInstaller.install(claude: "/x/claude", bundlePlugin: "/App/ClaudePlugin", runner: runner,
                                                   ensureCLI: { order.append("cli"); if !runner.calls.isEmpty { order.append("late") } })
        #expect(throws: Never.self) { try result.get() }
        #expect(order == ["cli"])
        #expect(runner.calls == ClaudePluginInstaller.installCommands(claude: "/x/claude", bundlePlugin: "/App/ClaudePlugin"))
    }

    @Test func installStopsIfTheCLILinkFails() {
        let runner = FakeRunner([])
        let result = ClaudePluginInstaller.install(claude: "/x/claude", bundlePlugin: "/p", runner: runner,
                                                   ensureCLI: { throw CLIInstallerError.notALink })
        #expect(failure(result) == .cli(CLIInstallerError.notALink.errorDescription ?? ""))
        #expect(runner.calls.isEmpty)
    }

    @Test func installStopsAtTheFirstFailureAndTrimsStderr() {
        let long = String(repeating: "x", count: 500)
        let runner = FakeRunner([ToolResult(status: 1, stderr: "  \(long)\n"), ToolResult(status: 0)])
        let result = ClaudePluginInstaller.install(claude: "/x/claude", bundlePlugin: "/p", runner: runner, ensureCLI: {})
        let error = failure(result)
        #expect(runner.calls.count == 1)
        #expect((error?.message.count ?? 999) <= 300)
        #expect(error?.message.hasPrefix("xxx") == true)
    }

    @Test func installFailureOnTheSecondCommand() {
        let runner = FakeRunner([ToolResult(status: 0), ToolResult(status: 2, stderr: "no such plugin\n")])
        let result = ClaudePluginInstaller.install(claude: "/x/claude", bundlePlugin: "/p", runner: runner, ensureCLI: {})
        #expect(failure(result) == .command("no such plugin"))
        #expect(runner.calls.count == 2)
    }
}

import Foundation
import MooringIPC
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

    @Test func marketplaceStepsAddWhenNotRegistered() {
        #expect(ClaudePluginInstaller.marketplaceSteps(claude: "/x/claude", bundlePlugin: "/App/ClaudePlugin", registered: nil)
            == [["/x/claude", "plugin", "marketplace", "add", "/App/ClaudePlugin"]])
    }

    @Test func marketplaceStepsUpdateWhenTheSamePath() {
        let same = ClaudeCode.Marketplace(name: "mooring-app", path: "/App/ClaudePlugin/")
        #expect(ClaudePluginInstaller.marketplaceSteps(claude: "/x/claude", bundlePlugin: "/App/ClaudePlugin", registered: same)
            == [["/x/claude", "plugin", "marketplace", "update", "mooring-app"]])
    }

    @Test func marketplaceStepsUpdateWhenThePathIsUnknown() {
        let unknown = ClaudeCode.Marketplace(name: "mooring-app", path: nil)
        #expect(ClaudePluginInstaller.marketplaceSteps(claude: "/x/claude", bundlePlugin: "/App/ClaudePlugin", registered: unknown)
            == [["/x/claude", "plugin", "marketplace", "update", "mooring-app"]])
    }

    @Test func marketplaceStepsRemoveThenAddWhenTheAppMoved() {
        let moved = ClaudeCode.Marketplace(name: "mooring-app", path: "/Old/Mooring.app/Contents/Resources/ClaudePlugin")
        #expect(ClaudePluginInstaller.marketplaceSteps(claude: "/x/claude", bundlePlugin: "/App/ClaudePlugin", registered: moved) == [
            ["/x/claude", "plugin", "marketplace", "remove", "mooring-app"],
            ["/x/claude", "plugin", "marketplace", "add", "/App/ClaudePlugin"]
        ])
    }

    @Test func pluginCommandInstallsWhenAbsentAndUpdatesWhenInstalled() {
        #expect(ClaudePluginInstaller.pluginCommand(claude: "/x/claude", installed: false)
            == ["/x/claude", "plugin", "install", "mooring@mooring-app", "-y"])
        #expect(ClaudePluginInstaller.pluginCommand(claude: "/x/claude", installed: true)
            == ["/x/claude", "plugin", "update", "mooring@mooring-app", "-y"])
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

    private static let marketplaceList = ToolResult(status: 0, stdout: Data(#"[{"name":"mooring-app","source":"directory"}]"#.utf8))
    private static let otherMarketplaces = ToolResult(status: 0, stdout: Data(#"[{"name":"claude-plugins-official"}]"#.utf8))
    private static let pluginListWithApp = ToolResult(
        status: 0, stdout: listJSON([Entry(id: "mooring@mooring-app", version: "0.9", enabled: true)]))
    private static let pluginListWithout = ToolResult(status: 0, stdout: listJSON([]))

    private func install(_ runner: FakeRunner, ensureCLI: () throws -> Void = {}) -> Result<Void, ClaudePluginInstaller.InstallError> {
        ClaudePluginInstaller.install(claude: "/x/claude", bundlePlugin: "/App/ClaudePlugin", runner: runner, ensureCLI: ensureCLI)
    }

    @Test func firstInstallListsThenAddsAndInstalls() {
        let runner = FakeRunner([Self.otherMarketplaces, ToolResult(status: 0), Self.pluginListWithout, ToolResult(status: 0)])
        var order: [String] = []
        let result = install(runner, ensureCLI: { order.append("cli"); if !runner.calls.isEmpty { order.append("late") } })
        #expect(throws: Never.self) { try result.get() }
        #expect(order == ["cli"])
        #expect(runner.calls == [
            ["/x/claude", "plugin", "marketplace", "list", "--json"],
            ["/x/claude", "plugin", "marketplace", "add", "/App/ClaudePlugin"],
            ["/x/claude", "plugin", "list", "--json"],
            ["/x/claude", "plugin", "install", "mooring@mooring-app", "-y"]
        ])
    }

    @Test func updateRefreshesTheMarketplaceThenUpdatesThePlugin() {
        let runner = FakeRunner([Self.marketplaceList, ToolResult(status: 0), Self.pluginListWithApp, ToolResult(status: 0)])
        let result = install(runner)
        #expect(throws: Never.self) { try result.get() }
        #expect(runner.calls == [
            ["/x/claude", "plugin", "marketplace", "list", "--json"],
            ["/x/claude", "plugin", "marketplace", "update", "mooring-app"],
            ["/x/claude", "plugin", "list", "--json"],
            ["/x/claude", "plugin", "update", "mooring@mooring-app", "-y"]
        ])
    }

    @Test func registeredMarketplaceWithoutThePluginInstalls() {
        let runner = FakeRunner([Self.marketplaceList, ToolResult(status: 0), Self.pluginListWithout, ToolResult(status: 0)])
        _ = install(runner)
        #expect(runner.calls[1] == ["/x/claude", "plugin", "marketplace", "update", "mooring-app"])
        #expect(runner.calls[3] == ["/x/claude", "plugin", "install", "mooring@mooring-app", "-y"])
    }

    @Test func movedAppRemovesAndReAddsTheMarketplaceThenInstalls() {
        let moved = ToolResult(status: 0, stdout: Data(#"[{"name":"mooring-app","source":"directory","path":"/Old/ClaudePlugin"}]"#.utf8))
        let runner = FakeRunner([moved, ToolResult(status: 0), ToolResult(status: 0), Self.pluginListWithout, ToolResult(status: 0)])
        let result = install(runner)
        #expect(throws: Never.self) { try result.get() }
        #expect(runner.calls == [
            ["/x/claude", "plugin", "marketplace", "list", "--json"],
            ["/x/claude", "plugin", "marketplace", "remove", "mooring-app"],
            ["/x/claude", "plugin", "marketplace", "add", "/App/ClaudePlugin"],
            ["/x/claude", "plugin", "list", "--json"],
            ["/x/claude", "plugin", "install", "mooring@mooring-app", "-y"]
        ])
    }

    @Test func samePathUpdatesTheMarketplace() {
        let same = ToolResult(status: 0, stdout: Data(#"[{"name":"mooring-app","source":"directory","path":"/App/ClaudePlugin"}]"#.utf8))
        let runner = FakeRunner([same, ToolResult(status: 0), Self.pluginListWithApp, ToolResult(status: 0)])
        _ = install(runner)
        #expect(runner.calls[1] == ["/x/claude", "plugin", "marketplace", "update", "mooring-app"])
        #expect(runner.calls[3] == ["/x/claude", "plugin", "update", "mooring@mooring-app", "-y"])
    }

    @Test func missingPathFieldUpdatesTheMarketplace() {
        // marketplaceList has no `path` field.
        let runner = FakeRunner([Self.marketplaceList, ToolResult(status: 0), Self.pluginListWithApp, ToolResult(status: 0)])
        _ = install(runner)
        #expect(runner.calls[1] == ["/x/claude", "plugin", "marketplace", "update", "mooring-app"])
    }

    @Test func installStopsIfTheCLILinkFails() {
        let runner = FakeRunner([])
        let result = install(runner, ensureCLI: { throw CLIInstallerError.notALink })
        #expect(failure(result) == .cli(CLIInstallerError.notALink.errorDescription ?? ""))
        #expect(runner.calls.isEmpty)
    }

    @Test func installStopsAtTheFirstFailureAndTrimsStderr() {
        let long = String(repeating: "x", count: 500)
        let runner = FakeRunner([Self.otherMarketplaces, ToolResult(status: 1, stderr: "  \(long)\n"), Self.pluginListWithout])
        let error = failure(install(runner))
        #expect(runner.calls.count == 2)
        #expect((error?.message.count ?? 999) <= 300)
        #expect(error?.message.hasPrefix("xxx") == true)
    }

    @Test func aFailureWithNoStderrReportsTheExitStatus() {
        for blank in ["", "  \n\t"] {
            let runner = FakeRunner([ToolResult(status: 3, stderr: blank)])
            #expect(failure(install(runner)) == .command("Failed (exit 3)"))
        }
    }

    @Test func aTimeoutWithNoStderrSaysTimedOut() {
        let runner = FakeRunner([Self.otherMarketplaces, ToolResult(status: 124, stderr: " \n")])
        #expect(failure(install(runner)) == .command("Timed out"))
    }

    @Test func installStopsWhenAListFails() {
        let runner = FakeRunner([ToolResult(status: 1, stderr: "boom\n")])
        #expect(failure(install(runner)) == .command("boom"))
        #expect(runner.calls.count == 1)
    }

    @Test func installFailureOnTheLastCommand() {
        let runner = FakeRunner([Self.marketplaceList, ToolResult(status: 0), Self.pluginListWithout,
                                 ToolResult(status: 2, stderr: "no such plugin\n")])
        #expect(failure(install(runner)) == .command("no such plugin"))
        #expect(runner.calls.count == 4)
    }

    /// Uninstall removes the app's marketplace, which takes its plugin with it, and leaves a GitHub install alone.
    @Test func uninstallRemovesOnlyTheAppMarketplace() {
        let registered = FakeRunner([Self.marketplaceList, ToolResult(status: 0)])
        #expect(failure(ClaudePluginInstaller.uninstall(claude: "/x/claude", runner: registered)) == nil)
        #expect(registered.calls == [
            ["/x/claude", "plugin", "marketplace", "list", "--json"],
            ["/x/claude", "plugin", "marketplace", "remove", "mooring-app"]
        ])

        let absent = FakeRunner([Self.otherMarketplaces])
        #expect(failure(ClaudePluginInstaller.uninstall(claude: "/x/claude", runner: absent)) == nil)
        #expect(absent.calls == [["/x/claude", "plugin", "marketplace", "list", "--json"]])

        let failing = FakeRunner([Self.marketplaceList, ToolResult(status: 1, stderr: "boom\n")])
        #expect(failure(ClaudePluginInstaller.uninstall(claude: "/x/claude", runner: failing)) == .command("boom"))
    }
}

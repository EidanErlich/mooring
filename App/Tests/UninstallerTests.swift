import Foundation
import MooringIPC
import Testing
@testable import Mooring

private struct FakeStepError: LocalizedError {
    let errorDescription: String?
}

/// Records every step it's asked to do, failing the ones named in `failing`. Touches nothing real.
@MainActor
private final class FakeUninstallSteps: UninstallPerforming {
    enum Call: Equatable {
        case perform(UninstallStep)
        case report([UninstallFailure])
        case quit
    }

    private(set) var calls: [Call] = []
    var failing: [UninstallStep: String] = [:]
    /// When set, the first step waits here until the test resumes it.
    var holdsFirstStep = false
    private(set) var held: CheckedContinuation<Void, Never>?

    func perform(_ step: UninstallStep) async throws {
        calls.append(.perform(step))
        if holdsFirstStep, calls.count == 1 { await withCheckedContinuation { held = $0 } }
        if let message = failing[step] { throw FakeStepError(errorDescription: message) }
    }

    func release() {
        held?.resume()
        held = nil
    }

    func report(_ failures: [UninstallFailure]) async {
        calls.append(.report(failures))
    }

    func quit() {
        calls.append(.quit)
    }

    var performed: [UninstallStep] {
        calls.compactMap { if case .perform(let step) = $0 { step } else { nil } }
    }
}

/// A model over a fake, counting how many times it built the real steps.
@MainActor
private final class ModelHarness {
    let steps = FakeUninstallSteps()
    private(set) var made = 0
    private(set) var model: UninstallModel!

    init() {
        model = UninstallModel { [unowned self] in
            made += 1
            return steps
        }
    }
}

@MainActor
struct UninstallerTests {
    private let fileManager = FileManager.default

    private func makeTempFolder() throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent("mooring-uninstall-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Sleep is restored before the helper goes, every step runs even after one fails, and the failures are
    /// shown before quitting.
    @Test func uninstallOrderAndContinuesAfterFailure() async {
        let steps = FakeUninstallSteps()
        steps.failing = [.restoreSleep: "The helper timed out", .removeClaudePlugin: "claude exited 1"]
        let failures = await Uninstaller.run(deleteClipboardHistory: true, using: steps)

        let order: [UninstallStep] = [
            .endLeases, .restoreSleep, .unregisterHelper, .unregisterLoginItem, .removeCLILink, .removeClaudePlugin,
            .removeMCPEntries, .deleteClipboardHistory, .removeSupportFiles, .removeSettings, .moveAppToTrash
        ]
        let expected = [
            UninstallFailure(step: .restoreSleep, message: "The helper timed out"),
            UninstallFailure(step: .removeClaudePlugin, message: "claude exited 1")
        ]
        #expect(steps.calls == order.map { .perform($0) } + [.report(expected), .quit])
        #expect(failures == expected)

        // Nothing failed: no summary, straight to quitting.
        let clean = FakeUninstallSteps()
        #expect(await Uninstaller.run(deleteClipboardHistory: true, using: clean).isEmpty)
        #expect(clean.calls == order.map { .perform($0) } + [.quit])
    }

    /// The box starts unticked each time the sheet opens, and history goes only when it's ticked.
    @Test func clipboardDeletedOnlyWhenTicked() async {
        let unticked = FakeUninstallSteps()
        await Uninstaller.run(deleteClipboardHistory: false, using: unticked)
        #expect(!unticked.performed.contains(.deleteClipboardHistory))
        #expect(unticked.performed.contains(.removeSettings))

        let harness = ModelHarness()
        harness.model.deleteClipboardHistory = true
        harness.model.present()
        #expect(harness.model.isPresented)
        #expect(!harness.model.deleteClipboardHistory)
        await harness.model.uninstall()
        #expect(!harness.steps.performed.contains(.deleteClipboardHistory))

        let ticked = ModelHarness()
        ticked.model.present()
        ticked.model.deleteClipboardHistory = true
        await ticked.model.uninstall()
        #expect(ticked.steps.performed.contains(.deleteClipboardHistory))
        #expect(ticked.steps.calls.last == .quit)
        #expect(!ticked.model.isPresented)
    }

    /// Only a link that leads to this app's binary is removed; anything else at the path is left alone.
    @Test func cliLinkRemovedOnlyIfOurs() throws {
        let root = try makeTempFolder()
        defer { try? fileManager.removeItem(at: root) }
        let target = root.appendingPathComponent("Mooring.app/Contents/Helpers/mooring")
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: target)
        let link = root.appendingPathComponent("home/.local/bin/mooring")

        // Missing: nothing to do.
        #expect(try !CLIInstaller.removeIfOurs(link: link, target: target))

        // Ours: removed, and the binary it led to is still there.
        try CLIInstaller.install(link: link, target: target)
        #expect(try CLIInstaller.removeIfOurs(link: link, target: target))
        #expect(CLIInstaller.state(link: link, target: target) == .missing)
        #expect(fileManager.fileExists(atPath: target.path))

        // Someone else's link: kept.
        let other = root.appendingPathComponent("Other.app/Contents/Helpers/mooring")
        try CLIInstaller.install(link: link, target: other)
        #expect(try !CLIInstaller.removeIfOurs(link: link, target: target))
        #expect(try fileManager.destinationOfSymbolicLink(atPath: link.path) == other.path)

        // A regular file: kept.
        try fileManager.removeItem(at: link)
        try Data("mine".utf8).write(to: link)
        #expect(try !CLIInstaller.removeIfOurs(link: link, target: target))
        #expect(try Data(contentsOf: link) == Data("mine".utf8))
    }

    /// Cancel closes the sheet without building or running a single step.
    @Test func cancelDoesNothing() {
        let harness = ModelHarness()
        harness.model.present()
        harness.model.deleteClipboardHistory = true
        harness.model.cancel()
        #expect(!harness.model.isPresented)
        #expect(harness.made == 0)
        #expect(harness.steps.calls.isEmpty)
    }

    /// Only entries that run this app's `mooring` are removed; other servers and other Moorings stay.
    @Test func mcpEntriesRemovedOnlyWhenTheyPointAtThisApp() throws {
        let home = try makeTempFolder()
        defer { try? fileManager.removeItem(at: home) }
        let helper = "/Applications/Mooring.app/Contents/Helpers/mooring"
        let desktop = MCPClientConfig(client: .claudeDesktop, home: home)
        let cursor = MCPClientConfig(client: .cursor, home: home)
        for config in [desktop, cursor] {
            try fileManager.createDirectory(at: config.folderURL, withIntermediateDirectories: true)
        }
        try desktop.add(helperPath: helper)
        try cursor.add(helperPath: "/somewhere/else/mooring")

        try Uninstaller.removeMCPEntries(home: home, helperPath: helper)
        #expect(desktop.state(helperPath: helper) == .notAdded)
        #expect(cursor.state(helperPath: helper) == .needsUpdate("/somewhere/else/mooring"))
    }

    /// Only Mooring's own files go from its Application Support folder; anything else there stays, and the folder
    /// goes only once it's empty. Clipboard history is the checkbox's, so it stays too.
    @Test func uninstallRemovesOnlyMooringFiles() throws {
        let root = try makeTempFolder()
        defer { try? fileManager.removeItem(at: root) }
        let folder = root.appendingPathComponent("Mooring", isDirectory: true)
        try fileManager.createDirectory(at: folder.appendingPathComponent("Clipboard"), withIntermediateDirectories: true)
        for name in ["leases.json", "layouts.json", "mooring.sock", "notes.txt", "leases.json.bak", "Clipboard/Storage.sqlite"] {
            try Data(name.utf8).write(to: folder.appendingPathComponent(name))
        }
        #expect(Uninstaller.supportFileNames == ["leases.json", "layouts.json", "mooring.sock"])

        try Uninstaller.removeSupportFiles(in: folder)
        let left = try fileManager.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(left == ["Clipboard", "leases.json.bak", "notes.txt"])
        #expect(fileManager.fileExists(atPath: folder.appendingPathComponent("Clipboard/Storage.sqlite").path))

        // Only Mooring's files: the folder goes too.
        let ours = root.appendingPathComponent("Only ours", isDirectory: true)
        try fileManager.createDirectory(at: ours, withIntermediateDirectories: true)
        for name in Uninstaller.supportFileNames { try Data().write(to: ours.appendingPathComponent(name)) }
        try Uninstaller.removeSupportFiles(in: ours)
        #expect(!fileManager.fileExists(atPath: ours.path))

        // No folder: nothing to do.
        try Uninstaller.removeSupportFiles(in: root.appendingPathComponent("Missing", isDirectory: true))
        #expect(UninstallStep.removeSupportFiles.title == "Delete saved sessions, layouts and the CLI socket")
    }

    /// If lid sleep couldn't be turned back on, the summary says how to do it by hand.
    @Test func restoreSleepFailureShowsPmsetHint() {
        let hint = "Sleep may still be disabled. Run in Terminal: sudo pmset -a disablesleep 0"
        let failed = Uninstaller.summary([UninstallFailure(step: .restoreSleep, message: "The helper timed out")])
        #expect(failed.contains("• Turn lid sleep back on: The helper timed out"))
        #expect(failed.contains(hint))
        #expect(failed.hasSuffix("Mooring will quit now."))

        let other = Uninstaller.summary([UninstallFailure(step: .removeClaudePlugin, message: "claude exited 1")])
        #expect(!other.contains(hint))
        #expect(other.contains("claude exited 1"))
    }

    /// Removing Mooring's MCP entry keeps every other server, and the rest of the file, as they were.
    @Test func mcpUninstallKeepsOtherServers() throws {
        let home = try makeTempFolder()
        defer { try? fileManager.removeItem(at: home) }
        let helper = "/Applications/Mooring.app/Contents/Helpers/mooring"
        let desktop = MCPClientConfig(client: .claudeDesktop, home: home)
        try fileManager.createDirectory(at: desktop.folderURL, withIntermediateDirectories: true)
        let original: [String: Any] = [
            "globalShortcut": "Cmd+Shift+Space",
            "mcpServers": ["other": ["command": "/usr/local/bin/other", "args": ["serve"]]]
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: desktop.fileURL)
        try desktop.add(helperPath: helper)

        try Uninstaller.removeMCPEntries(home: home, helperPath: helper)
        #expect(desktop.state(helperPath: helper) == .notAdded)
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: desktop.fileURL)) as? [String: Any])
        #expect(root["globalShortcut"] as? String == "Cmd+Shift+Space")
        let servers = try #require(root["mcpServers"] as? [String: Any])
        #expect(Array(servers.keys) == ["other"])
        let other = try #require(servers["other"] as? [String: Any])
        #expect(other["command"] as? String == "/usr/local/bin/other")
        #expect(other["args"] as? [String] == ["serve"])
    }

    /// While an uninstall runs, a second click and Cancel are ignored: the steps are built and run once.
    @Test func uninstallIgnoredWhileRunning() async {
        let harness = ModelHarness()
        harness.steps.holdsFirstStep = true
        harness.model.present()
        let first = Task { await harness.model.uninstall() }
        while harness.steps.held == nil { await Task.yield() }
        #expect(harness.model.isRunning)

        await harness.model.uninstall()
        harness.model.cancel()
        #expect(harness.model.isPresented)
        #expect(harness.made == 1)
        #expect(harness.steps.calls == [.perform(.endLeases)])

        harness.steps.release()
        await first.value
        #expect(harness.made == 1)
        #expect(harness.steps.performed == Uninstaller.steps(deleteClipboardHistory: false))
        #expect(harness.steps.calls.filter { $0 == .quit }.count == 1)
        #expect(!harness.model.isRunning)
        #expect(!harness.model.isPresented)
    }

    /// The settings domains go at the uninstall step and again at quit, so nothing written on the way out
    /// brings them back. Without an uninstall, quitting removes nothing.
    @Test func settingsRemovedAgainAtQuitAfterUninstall() {
        var removed: [String] = []
        let remover = SettingsDomainsRemover(domains: ["a", "b"]) { removed.append($0) }
        remover.removeAgainAtQuit()
        #expect(removed.isEmpty)
        remover.remove()
        #expect(removed == ["a", "b"])
        remover.removeAgainAtQuit()
        #expect(removed == ["a", "b", "a", "b"])
    }

    /// The sheet lists every step but the clipboard one (that's the checkbox), then quitting; the domains are
    /// Windows', Clipboard's and the app's own.
    @Test func sheetListsStepsAndDomains() {
        #expect(UninstallModel.plannedSteps.count == UninstallStep.allCases.count)
        #expect(UninstallModel.plannedSteps.last == "Quit Mooring")
        #expect(!UninstallModel.plannedSteps.contains(UninstallStep.deleteClipboardHistory.title))
        #expect(Uninstaller.settingsDomains(appDomain: "dev.mooring.app")
            == ["dev.mooring.windows", "dev.mooring.clipboard", "dev.mooring.app"])
        #expect(AdvancedSettingsPage.uninstallTitle == "Uninstall Mooring…")
        // The caption names what goes, rather than claiming "everything".
        for part in ["helper", "login item", "mooring command", "Claude Code plugin", "Claude Desktop and Cursor",
                     "saved sessions and layouts", "settings", "Trash", "Clipboard history"] {
            #expect(AdvancedSettingsPage.uninstallCaption.contains(part))
        }
        #expect(!AdvancedSettingsPage.uninstallCaption.contains("everything"))
        #expect(AdvancedSettingsPage.sections(updates: nil).last == .uninstall)
    }
}

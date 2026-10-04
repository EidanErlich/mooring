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

    func perform(_ step: UninstallStep) async throws {
        calls.append(.perform(step))
        if let message = failing[step] { throw FakeStepError(errorDescription: message) }
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
            .removeMCPEntries, .deleteClipboardHistory, .removeSettings, .moveAppToTrash
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

    /// The sheet lists every step but the clipboard one (that's the checkbox), then quitting; the domains are
    /// Windows', Clipboard's and the app's own.
    @Test func sheetListsStepsAndDomains() {
        #expect(UninstallModel.plannedSteps.count == UninstallStep.allCases.count)
        #expect(UninstallModel.plannedSteps.last == "Quit Mooring")
        #expect(!UninstallModel.plannedSteps.contains(UninstallStep.deleteClipboardHistory.title))
        #expect(Uninstaller.settingsDomains(appDomain: "dev.mooring.app")
            == ["dev.mooring.windows", "dev.mooring.clipboard", "dev.mooring.app"])
        #expect(AdvancedSettingsPage.uninstallTitle == "Uninstall Mooring…")
        #expect(AdvancedSettingsPage.sections(updates: nil).last == .uninstall)
    }
}

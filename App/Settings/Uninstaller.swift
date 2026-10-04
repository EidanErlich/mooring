import AppKit
import AwakeKit
import ClipKit
import Foundation
import MooringIPC
import Observation
import os
import ServiceManagement

/// One step of Settings → Advanced → "Uninstall Mooring…" (SPEC Appendix A), in the order they run.
enum UninstallStep: CaseIterable, Hashable, Sendable {
    case endLeases, restoreSleep, unregisterHelper, unregisterLoginItem, removeCLILink, removeClaudePlugin,
         removeMCPEntries, deleteClipboardHistory, removeSettings, moveAppToTrash

    /// The step in plain words, for the sheet and the failure summary.
    var title: String {
        switch self {
        case .endLeases: "End every keep-awake session, so the Mac sleeps normally again"
        case .restoreSleep: "Turn lid sleep back on"
        case .unregisterHelper: "Remove Mooring's helper"
        case .unregisterLoginItem: "Stop opening at login"
        case .removeCLILink: "Remove the mooring command from ~/.local/bin, if it links to this app"
        case .removeClaudePlugin: "Remove the Claude Code plugin that came with the app"
        case .removeMCPEntries: "Remove Mooring from Claude Desktop and Cursor"
        case .deleteClipboardHistory: "Delete clipboard history"
        case .removeSettings: "Delete Mooring's settings"
        case .moveAppToTrash: "Move Mooring to the Trash"
        }
    }
}

/// A step that failed, and why.
struct UninstallFailure: Equatable {
    let step: UninstallStep
    let message: String
}

/// Does the steps. `LiveUninstallSteps` is the real one; tests record calls instead, so nothing real is touched.
@MainActor
protocol UninstallPerforming: AnyObject {
    func perform(_ step: UninstallStep) async throws
    /// Lists what failed and waits until the user has seen it. Called only when something failed.
    func report(_ failures: [UninstallFailure]) async
    func quit()
}

/// Runs the steps in order. A failing step is recorded and the rest still run, since each undoes something
/// separate; then any failures are shown, and the app quits.
@MainActor
enum Uninstaller {
    /// The steps to run; the clipboard history goes only when its box is ticked.
    static func steps(deleteClipboardHistory: Bool) -> [UninstallStep] {
        UninstallStep.allCases.filter { $0 != .deleteClipboardHistory || deleteClipboardHistory }
    }

    @discardableResult
    static func run(deleteClipboardHistory: Bool, using performer: any UninstallPerforming) async -> [UninstallFailure] {
        let log = Logger(subsystem: "dev.mooring", category: "uninstall")
        var failures: [UninstallFailure] = []
        for step in steps(deleteClipboardHistory: deleteClipboardHistory) {
            do {
                try await performer.perform(step)
                log.notice("uninstall: \(String(describing: step), privacy: .public) done")
            } catch {
                let message = error.localizedDescription
                log.error("uninstall: \(String(describing: step), privacy: .public) failed: \(message, privacy: .public)")
                failures.append(UninstallFailure(step: step, message: message))
            }
        }
        if !failures.isEmpty { await performer.report(failures) }
        performer.quit()
        return failures
    }

    /// Windows' and Clipboard's settings suites, then the app's own domain.
    static func settingsDomains(appDomain: String) -> [String] {
        ["dev.mooring.windows", "dev.mooring.clipboard", appDomain]
    }

    /// Removes the Claude Desktop and Cursor entries that run `helperPath` (this app's `mooring`). An entry pointing
    /// anywhere else is left alone. Tries every client, then throws the first error.
    static func removeMCPEntries(home: URL, helperPath: String) throws {
        var firstError: Error?
        for client in MCPClientConfig.Client.allCases {
            let config = MCPClientConfig(client: client, home: home)
            guard config.state(helperPath: helperPath) == .added else { continue }
            do {
                try config.remove()
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}

/// What the "Uninstall Mooring…" sheet shows and does. Cancel runs nothing.
@MainActor
@Observable
final class UninstallModel {
    var isPresented = false
    var deleteClipboardHistory = false
    private(set) var isRunning = false

    @ObservationIgnored private let makeSteps: @MainActor () -> any UninstallPerforming

    /// `makeSteps` is called only when Uninstall is clicked.
    init(makeSteps: @escaping @MainActor () -> any UninstallPerforming) {
        self.makeSteps = makeSteps
    }

    /// The model for the running app; nothing real is built until Uninstall is clicked.
    static func live() -> UninstallModel {
        UninstallModel { LiveUninstallSteps.live() }
    }

    /// What the sheet lists. The clipboard step is left out: the checkbox stands for it.
    static var plannedSteps: [String] {
        Uninstaller.steps(deleteClipboardHistory: false).map(\.title) + ["Quit Mooring"]
    }

    /// Opens the sheet with the box unticked.
    func present() {
        deleteClipboardHistory = false
        isPresented = true
    }

    func cancel() {
        guard !isRunning else { return }
        isPresented = false
    }

    func uninstall() async {
        guard isPresented, !isRunning else { return }
        isRunning = true
        await Uninstaller.run(deleteClipboardHistory: deleteClipboardHistory, using: makeSteps())
        isRunning = false
        isPresented = false
    }
}

private struct UninstallStepError: LocalizedError {
    let errorDescription: String?
}

/// The real steps, reusing what Settings already does: the engine, the lid controller and helper client,
/// `SMAppService`, `CLIInstaller`, `ClaudePluginInstaller`, `MCPClientConfig` and `ClipboardController`.
@MainActor
final class LiveUninstallSteps: UninstallPerforming {
    private let engine: AwakeEngine?
    private let lid: LidController?
    private let helper: any LidHelper
    private let clipboard: ClipboardController?

    init(engine: AwakeEngine?, lid: LidController?, helper: any LidHelper, clipboard: ClipboardController?) {
        self.engine = engine
        self.lid = lid
        self.helper = helper
        self.clipboard = clipboard
    }

    static func live() -> LiveUninstallSteps {
        let settings = SettingsWindowController.shared
        return LiveUninstallSteps(engine: settings.engine, lid: settings.lid, helper: HelperClient.shared,
                                  clipboard: settings.clipboard)
    }

    func perform(_ step: UninstallStep) async throws {
        switch step {
        case .endLeases: endLeases()
        case .restoreSleep: try await restoreSleep()
        case .unregisterHelper: try await unregisterHelper()
        case .unregisterLoginItem: try unregisterLoginItem()
        case .removeCLILink: try CLIInstaller.removeIfOurs(link: CLIInstaller.defaultLink, target: CLIInstaller.bundledBinary)
        case .removeClaudePlugin: try await removeClaudePlugin()
        case .removeMCPEntries:
            try Uninstaller.removeMCPEntries(home: FileManager.default.homeDirectoryForCurrentUser,
                                             helperPath: MCPClientsModel.bundledHelperPath(in: Bundle.main.bundleURL))
        case .deleteClipboardHistory: try deleteClipboardHistory()
        case .removeSettings: removeSettings()
        case .moveAppToTrash: _ = try await NSWorkspace.shared.recycle([Bundle.main.bundleURL])
        }
    }

    /// Releasing every lease makes the engine drop its assertions and ask for lid sleep back.
    private func endLeases() {
        guard let engine else { return }
        for lease in engine.leases { engine.release(id: lease.id) }
    }

    /// Stops lid mode coming back (as quitting does), then has the helper confirm `disablesleep 0`.
    /// Without an enabled helper there is nothing it could have set.
    private func restoreSleep() async throws {
        await lid?.shutDown()
        guard helper.status == .enabled else { return }
        try await helper.setLidSleepDisabled(false)
    }

    private func unregisterHelper() async throws {
        guard helper.status == .enabled || helper.status == .requiresApproval else { return }
        try await helper.unregister()
    }

    private func unregisterLoginItem() throws {
        let app = SMAppService.mainApp
        guard app.status == .enabled || app.status == .requiresApproval else { return }
        try app.unregister()
    }

    /// Finding and running `claude` blocks, so it happens off the main actor. No `claude`, nothing to remove.
    private func removeClaudePlugin() async throws {
        let result = await Task.detached {
            ClaudePluginInstaller.findClaude().map { ClaudePluginInstaller.uninstall(claude: $0, runner: ProcessRunner()) }
        }.value
        if case .failure(let error) = result { throw UninstallStepError(errorDescription: error.message) }
    }

    /// Turns Clipboard off and deletes its folder, pins included.
    private func deleteClipboardHistory() throws {
        if let clipboard {
            if clipboard.isOn { clipboard.turnOff() }
            clipboard.deleteHistory()
        }
        // `deleteHistory` doesn't say whether it worked; this does.
        let folder = ClipKit.defaultStoreURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    private func removeSettings() {
        let appDomain = Bundle.main.bundleIdentifier ?? "dev.mooring.app"
        for domain in Uninstaller.settingsDomains(appDomain: appDomain) {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
    }

    func report(_ failures: [UninstallFailure]) async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Some steps didn't finish"
        alert.informativeText = failures.map { "• \($0.step.title): \($0.message)" }.joined(separator: "\n")
            + "\n\nMooring will quit now."
        alert.addButton(withTitle: "Quit")
        NSApp.activate()
        alert.runModal()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

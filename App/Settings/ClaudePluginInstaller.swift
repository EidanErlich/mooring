import Foundation
import MooringIPC

/// What a finished command left behind.
struct ToolResult {
    var status: Int32
    var stdout = Data()
    var stderr = ""
}

/// Runs an external tool to completion. A seam so tests never run a real `claude`.
protocol ToolRunning: Sendable {
    func run(_ argv: [String]) -> ToolResult
}

/// Runs a command with `Process`, killing it after `timeout` seconds. Blocks, so call it off the main actor.
/// Never blocks past the limit plus a few seconds, even when the command's children keep its pipes open.
struct ProcessRunner: ToolRunning {
    var timeout: TimeInterval = 30

    /// Collects one pipe's output and leaves `group` once, when the pipe reaches end of file.
    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var finished = false
        private let group: DispatchGroup

        init(group: DispatchGroup) {
            self.group = group
            group.enter()
        }

        func attach(to pipe: Pipe) {
            pipe.fileHandleForReading.readabilityHandler = { [self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    finish()
                } else {
                    lock.withLock { data.append(chunk) }
                }
            }
        }

        private func finish() {
            let first = lock.withLock { () -> Bool in
                defer { finished = true }
                return !finished
            }
            if first { group.leave() }
        }

        var value: Data { lock.withLock { data } }
    }

    /// The app's environment with a PATH that suits a tool launched from a GUI app: the tool's own folder first,
    /// so an npm-installed `claude` (`#!/usr/bin/env node`) finds the `node` beside it, then the usual install folders.
    static func environment(for executable: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let folder = (executable as NSString).deletingLastPathComponent
        let fixed = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = folder.isEmpty ? fixed : "\(folder):\(fixed)"
        return environment
    }

    func run(_ argv: [String]) -> ToolResult {
        guard let executable = argv.first else { return ToolResult(status: 127, stderr: "No command") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(argv.dropFirst())
        process.environment = Self.environment(for: executable)
        let (outPipe, errPipe) = (Pipe(), Pipe())
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice
        let eof = DispatchGroup()
        let (out, err) = (Output(group: eof), Output(group: eof))
        out.attach(to: outPipe)
        err.attach(to: errPipe)
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        func detach() {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
        }
        do {
            try process.run()
        } catch {
            detach()
            return ToolResult(status: 127, stderr: error.localizedDescription)
        }
        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
        }
        // Children can keep the pipes open after the command is gone, so give end of file a moment, then move on.
        _ = eof.wait(timeout: .now() + 1)
        detach()
        var message = String(bytes: err.value, encoding: .utf8) ?? ""
        if timedOut { message += "\nTimed out after \(Int(timeout)) seconds." }
        let status = timedOut || process.isRunning ? 124 : process.terminationStatus
        return ToolResult(status: status, stdout: out.value, stderr: message)
    }
}

/// Installs Mooring's plugin into Claude Code from the copy bundled in the app, and reports what is installed.
enum ClaudePluginInstaller {
    enum Status: Equatable {
        case claudeNotFound
        case notInstalled
        case installedFromApp(version: String)
        case installedFromGitHub(version: String)
        case needsUpdate(installed: String, app: String)

        var text: String {
            switch self {
            case .claudeNotFound: "Claude Code not found"
            case .notInstalled: "Not installed"
            case .installedFromApp: "Installed (from the app)"
            case .installedFromGitHub: "Installed (from GitHub)"
            case .needsUpdate: "Needs update"
            }
        }

        /// nil when there is nothing to do: the GitHub copy updates through GitHub, and without `claude` nothing can run.
        var buttonTitle: String? {
            switch self {
            case .notInstalled: "Install"
            case .needsUpdate: "Update"
            case .installedFromApp: "Reinstall"
            case .installedFromGitHub, .claudeNotFound: nil
            }
        }
    }

    enum InstallError: Error, Equatable {
        /// Linking `mooring` onto the PATH failed.
        case cli(String)
        /// A `claude` command exited non-zero; holds its trimmed stderr.
        case command(String)

        var message: String {
            switch self {
            case .cli(let message), .command(let message): message
            }
        }
    }

    /// What is installed, from `claude plugin list --json` output (nil when the command failed).
    static func status(listJSON: Data?, claudeFound: Bool, appVersion: String) -> Status {
        guard claudeFound else { return .claudeNotFound }
        guard let listJSON, let plugins = ClaudeCode.parsePluginList(listJSON),
              let plugin = ClaudeCode.mooringPlugin(in: plugins) else { return .notInstalled }
        let version = plugin.version ?? "unknown"
        if plugin.id == ClaudeCode.appPluginID {
            return version == appVersion ? .installedFromApp(version: version) : .needsUpdate(installed: version, app: appVersion)
        }
        return .installedFromGitHub(version: version)
    }

    /// True when the plugin is installed but switched off in Claude Code.
    static func isDisabled(listJSON: Data?) -> Bool {
        guard let listJSON, let plugins = ClaudeCode.parsePluginList(listJSON) else { return false }
        return ClaudeCode.mooringPlugin(in: plugins).map { !$0.enabled } ?? false
    }

    /// What to run for the bundled marketplace: register it when unknown, refresh it when it points at this app
    /// (`add` refuses a known name), and re-point it when the app moved. `remove` also uninstalls the marketplace's
    /// plugins, so the install that follows starts from scratch. A registration with no `path` is refreshed.
    static func marketplaceSteps(claude: String, bundlePlugin: String, registered: ClaudeCode.Marketplace?) -> [[String]] {
        let add = [claude, "plugin", "marketplace", "add", bundlePlugin]
        guard let registered else { return [add] }
        func standardized(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path }
        if let path = registered.path, standardized(path) != standardized(bundlePlugin) {
            return [[claude, "plugin", "marketplace", "remove", ClaudeCode.appMarketplaceName], add]
        }
        return [[claude, "plugin", "marketplace", "update", ClaudeCode.appMarketplaceName]]
    }

    /// Installs the plugin, or updates it when it is already installed from the app's marketplace.
    static func pluginCommand(claude: String, installed: Bool) -> [String] {
        [claude, "plugin", installed ? "update" : "install", ClaudeCode.appPluginID, "-y"]
    }

    /// The login shell's `claude` first (it sees the user's PATH), then the usual install locations.
    static func findClaude(loginShellLookup: () -> String?, isExecutable: (String) -> Bool) -> String? {
        if let found = loginShellLookup(), found.hasPrefix("/") { return found }
        return ClaudeCode.candidatePaths.map { ($0 as NSString).expandingTildeInPath }.first(where: isExecutable)
    }

    /// `/bin/zsh -lc 'command -v claude'`, limited to 3 seconds. Blocks.
    static func loginShellLookup(runner: ToolRunning = ProcessRunner(timeout: 3)) -> String? {
        let result = runner.run(["/bin/zsh", "-lc", "command -v claude"])
        guard result.status == 0 else { return nil }
        let text = String(bytes: result.stdout, encoding: .utf8) ?? ""
        // A `.zprofile` banner can print before `command -v` does, so the answer is the last absolute line.
        return text.split(whereSeparator: \.isNewline).last { $0.hasPrefix("/") }.map(String.init)
    }

    static func findClaude() -> String? {
        findClaude(loginShellLookup: { loginShellLookup() }, isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    /// Links `mooring` onto the PATH first (an installed plugin runs from Claude's cache, so its hook finds `mooring` there),
    /// then registers, refreshes or re-points the marketplace and installs or updates the plugin, stopping at the first failure.
    static func install(claude: String, bundlePlugin: String, runner: ToolRunning,
                        ensureCLI: () throws -> Void) -> Result<Void, InstallError> {
        do {
            try ensureCLI()
        } catch {
            return .failure(.cli(error.localizedDescription))
        }
        func run(_ argv: [String]) -> Result<Data, InstallError> {
            let result = runner.run(argv)
            guard result.status == 0 else {
                return .failure(.command(String(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))))
            }
            return .success(result.stdout)
        }
        let marketplaces = run([claude, "plugin", "marketplace", "list", "--json"])
        guard case .success(let marketplaceJSON) = marketplaces else { return marketplaces.map { _ in () } }
        let registered = ClaudeCode.parseMarketplaces(marketplaceJSON)?.first { $0.name == ClaudeCode.appMarketplaceName }
        for step in marketplaceSteps(claude: claude, bundlePlugin: bundlePlugin, registered: registered) {
            let marketplace = run(step)
            guard case .success = marketplace else { return marketplace.map { _ in () } }
        }
        let plugins = run([claude, "plugin", "list", "--json"])
        guard case .success(let pluginJSON) = plugins else { return plugins.map { _ in () } }
        let installed = ClaudeCode.parsePluginList(pluginJSON)?.contains { $0.id == ClaudeCode.appPluginID } ?? false
        return run(pluginCommand(claude: claude, installed: installed)).map { _ in () }
    }

    /// Links `mooring` into `~/.local/bin` when that isn't already done.
    static func ensureCLILinked() throws {
        guard CLIInstaller.state(link: CLIInstaller.defaultLink, target: CLIInstaller.bundledBinary) != .installed else { return }
        try CLIInstaller.install(link: CLIInstaller.defaultLink, target: CLIInstaller.bundledBinary)
    }

    /// `claude plugin list --json` output, or nil when it fails.
    static func readList(claude: String, runner: ToolRunning) -> Data? {
        let result = runner.run([claude, "plugin", "list", "--json"])
        return result.status == 0 ? result.stdout : nil
    }
}

import ArgumentParser
import Darwin
import Foundation
import MooringIPC

/// `mooring doctor`'s checks: is the app up, is this binary the one on PATH, and is the helper healthy.
public enum Doctor {
    public struct Check: Codable, Equatable, Sendable {
        public var name: String
        /// "pass", "fail" or "skip".
        public var state: String
        public var detail: String
        /// What to do about a failure; nil unless `state` is "fail".
        public var fix: String?

        public init(name: String, state: String, detail: String, fix: String?) {
            self.name = name
            self.state = state
            self.detail = detail
            self.fix = fix
        }
    }

    /// The seven checks in order. `status` is nil when the app didn't give a status, and `unavailable` says why, or
    /// `appError` holds the message of an error reply from an app that did answer; `resolve` follows symlinks;
    /// `claude` is nil when Claude Code wasn't found.
    public static func checks(
        status: StatusResult?, unavailable: CLIError = .unreachable, appError: String? = nil, pathEnv: String?,
        ownBinary: String, resolve: (String) -> String?, claude: ClaudeSnapshot?
    ) -> [Check] {
        [
            appCheck(status, unavailable: unavailable, appError: appError),
            pathCheck(pathEnv: pathEnv, ownBinary: ownBinary, resolve: resolve),
            helperCheck(status),
            lidCheck(status),
            pluginCheck(claude),
            claudeVersionCheck(claude),
            notificationsCheck(status)
        ]
    }

    /// One line per check, marked ✓, ✗ or –, with the fix after every ✗.
    public static func human(_ checks: [Check]) -> String {
        let width = (checks.map(\.name.count).max() ?? 0) + 2
        return checks.map { check in
            let name = check.name.padding(toLength: width, withPad: " ", startingAt: 0)
            switch check.state {
            case "pass": return "✓ \(name)\(check.detail)\n"
            case "fail": return "✗ \(name)\(check.detail)" + (check.fix.map { " — \($0)" } ?? "") + "\n"
            default: return "– \(name)\(check.detail)\n"
            }
        }.joined()
    }

    /// `path` with every symlink resolved, or nil when it doesn't exist.
    public static func resolvePath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func appCheck(_ status: StatusResult?, unavailable: CLIError, appError: String?) -> Check {
        guard let status else {
            if let appError {
                return Check(name: "App", state: "fail", detail: "answered with an error: \(appError)", fix: "Quit and reopen Mooring")
            }
            let detail = switch unavailable {
            case .noAnswer: "didn't answer"
            case .blocked: "permission denied"
            case .unreachable, .usage: "not running"
            }
            return Check(name: "App", state: "fail", detail: detail, fix: "Open Mooring")
        }
        return Check(name: "App", state: "pass", detail: status.summary, fix: nil)
    }

    private static func pathCheck(pathEnv: String?, ownBinary: String, resolve: (String) -> String?) -> Check {
        let name = "Command on PATH"
        let fix = "Settings → General → Install command-line tool, and add ~/.local/bin to PATH"
        let folders = (pathEnv ?? "").split(separator: ":").map(String.init)
        guard let found = folders.map({ $0 + "/mooring" }).first(where: isExecutableFile) else {
            return Check(name: name, state: "fail", detail: "not found on PATH", fix: fix)
        }
        guard (resolve(found) ?? found) == (resolve(ownBinary) ?? ownBinary) else {
            return Check(name: name, state: "fail", detail: "\(found) is another copy", fix: fix)
        }
        return Check(name: name, state: "pass", detail: found, fix: nil)
    }

    private static func helperCheck(_ status: StatusResult?) -> Check {
        guard let status else { return Check(name: "Helper", state: "skip", detail: "needs the app", fix: nil) }
        guard status.helper == "enabled" else {
            return Check(name: "Helper", state: "fail", detail: status.helper, fix: "Settings → Lid & Battery → Approve")
        }
        return Check(name: "Helper", state: "pass", detail: status.helper, fix: nil)
    }

    private static func lidCheck(_ status: StatusResult?) -> Check {
        let name = "Lid sleep"
        guard let status else { return Check(name: name, state: "skip", detail: "needs the app", fix: nil) }
        guard let actual = status.helperSleepDisabled else {
            return Check(name: name, state: "skip", detail: "the helper can't read it", fix: nil)
        }
        guard actual == status.lidSleepDisabled else {
            return Check(name: name, state: "fail", detail: actual ? "stuck disabled" : "mismatch",
                         fix: "Quit and reopen Mooring to restore sleep")
        }
        return Check(name: name, state: "pass", detail: "matches", fix: nil)
    }

    private static func pluginCheck(_ claude: ClaudeSnapshot?) -> Check {
        let name = "Claude plugin"
        guard let claude else { return Check(name: name, state: "skip", detail: "Claude Code not found", fix: nil) }
        let fix = "Settings → Awake → Agents → Install"
        // `claude` runs but its plugin list is unreadable (it failed or timed out): don't claim the plugin is missing.
        if claude.plugins == nil, claude.version != nil {
            return Check(name: name, state: "skip", detail: "couldn't check (claude plugin list failed)", fix: nil)
        }
        // With both the app's and the GitHub copy installed, either one enabled is enough; the app's copy is preferred.
        let copies = (claude.plugins ?? []).filter { $0.id == ClaudeCode.appPluginID || $0.id == ClaudeCode.repoPluginID }
        guard let plugin = copies.first(where: \.enabled) ?? ClaudeCode.mooringPlugin(in: copies) else {
            return Check(name: name, state: "fail", detail: "not installed", fix: fix)
        }
        guard plugin.enabled else { return Check(name: name, state: "fail", detail: "disabled", fix: fix) }
        let detail = [plugin.id, plugin.version].compactMap { $0 }.joined(separator: " ")
        return Check(name: name, state: "pass", detail: detail, fix: nil)
    }

    /// Passes when Claude Code's major.minor is the one the plugin was tested with. A different one only skips with a note,
    /// so a Claude Code update never makes `doctor` fail before Mooring ships a retest.
    private static func claudeVersionCheck(_ claude: ClaudeSnapshot?) -> Check {
        let name = "Claude Code version"
        guard let version = claude?.version, let tested = claude?.testedWith,
              let installed = ClaudeCode.majorMinor(version) else {
            return Check(name: name, state: "skip", detail: "unknown", fix: nil)
        }
        guard installed == tested else {
            return Check(name: name, state: "skip", detail: "tested with \(tested); you have \(version)", fix: nil)
        }
        return Check(name: name, state: "pass", detail: version, fix: nil)
    }

    /// Notifications carry lid approvals, so a denial only fails when the setting can ask for one.
    private static func notificationsCheck(_ status: StatusResult?) -> Check {
        let name = "Notifications"
        guard let status else { return Check(name: name, state: "skip", detail: "needs the app", fix: nil) }
        switch status.notifications {
        case "allowed": return Check(name: name, state: "pass", detail: "allowed", fix: nil)
        case "notDetermined": return Check(name: name, state: "skip", detail: "not asked yet", fix: nil)
        case "denied":
            guard ["askWhenOpenEnded", "alwaysAsk"].contains(status.agentLidApproval) else {
                return Check(name: name, state: "skip", detail: "denied (not needed)", fix: nil)
            }
            return Check(name: name, state: "fail", detail: "denied", fix: "System Settings → Notifications → Mooring")
        default: return Check(name: name, state: "skip", detail: "unknown", fix: nil)
        }
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && !isFolder.boolValue
            && access(path, X_OK) == 0
    }
}

struct DoctorCommand: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(commandName: "doctor", abstract: "Check that Mooring and the command are set up")

    @OptionGroup var output: OutputOptions

    func execute(_ env: CLIEnvironment) async -> Int32 {
        let app = await currentStatus(env)
        let checks = Doctor.checks(
            status: app.status, unavailable: app.unavailable, appError: app.error, pathEnv: env.pathEnv, ownBinary: env.ownBinaryPath,
            resolve: Doctor.resolvePath, claude: env.claude()
        )
        if output.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(["checks": checks]), let text = String(bytes: data, encoding: .utf8) else {
                env.writeError("mooring: Couldn't encode the checks\n")
                return 4
            }
            env.write(text + "\n")
        } else {
            env.write(Doctor.human(checks))
        }
        return checks.contains { $0.state == "fail" } ? 1 : 0
    }

    /// What asking the app for its status gave: the status, or why there is none. `error` is an error reply's message
    /// when the app answered with one; otherwise `unavailable` says why nothing usable came back.
    private struct AppReading {
        var status: StatusResult?
        var unavailable: CLIError = .unreachable
        var error: String?
    }

    /// The app's status, never launching it, so a stopped app shows as a failed check.
    private func currentStatus(_ env: CLIEnvironment) async -> AppReading {
        let request = Request(v: WireProtocol.version, id: env.newID(), op: .status, args: .status)
        do {
            let response = try await env.client.send(request, launch: false)
            if case .status(let status)? = response.result { return AppReading(status: status) }
            return AppReading(error: response.ok ? nil : response.error?.message ?? "unknown error")
        } catch let error as CLIError {
            return AppReading(unavailable: error)
        } catch {
            return AppReading()
        }
    }
}

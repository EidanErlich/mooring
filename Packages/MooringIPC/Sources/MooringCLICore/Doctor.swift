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

    /// The five checks in order. `status` is nil when the app didn't answer, and `unavailable` says why;
    /// `resolve` follows symlinks.
    public static func checks(
        status: StatusResult?, unavailable: CLIError = .unreachable, pathEnv: String?, ownBinary: String,
        resolve: (String) -> String?
    ) -> [Check] {
        [
            appCheck(status, unavailable: unavailable),
            pathCheck(pathEnv: pathEnv, ownBinary: ownBinary, resolve: resolve),
            helperCheck(status),
            lidCheck(status),
            Check(name: "Claude plugin", state: "skip", detail: "arrives in 2b", fix: nil)
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

    private static func appCheck(_ status: StatusResult?, unavailable: CLIError) -> Check {
        guard let status else {
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
        let (status, unavailable) = await currentStatus(env)
        let checks = Doctor.checks(
            status: status, unavailable: unavailable, pathEnv: env.pathEnv, ownBinary: env.ownBinaryPath,
            resolve: Doctor.resolvePath
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

    /// The app's status, never launching it, so a stopped app shows as a failed check; nil on any failure,
    /// with the reason it couldn't be read (`.unreachable` when the app answered with something else).
    private func currentStatus(_ env: CLIEnvironment) async -> (StatusResult?, CLIError) {
        let request = Request(v: WireProtocol.version, id: env.newID(), op: .status, args: .status)
        do {
            let response = try await env.client.send(request, launch: false)
            guard case .status(let status)? = response.result else { return (nil, .unreachable) }
            return (status, .unreachable)
        } catch let error as CLIError {
            return (nil, error)
        } catch {
            return (nil, .unreachable)
        }
    }
}

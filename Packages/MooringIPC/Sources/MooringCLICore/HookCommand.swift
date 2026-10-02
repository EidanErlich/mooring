import ArgumentParser
import Foundation
import MooringIPC
import os

/// `mooring hook <Event>`: turns one Claude Code hook payload (JSON on stdin) into a `hook` request.
///
/// It runs inside Claude Code's own hooks, so it must never disturb Claude: it prints nothing, never starts the app,
/// gives up quickly and always exits 0. Failures go to the unified log at debug level.
struct HookCommand: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(
        commandName: "hook", abstract: "Report a Claude Code hook event (used by the Mooring plugin)", shouldDisplay: false
    )

    /// The most stdin it will read; anything longer is not a hook payload.
    static let maxInputBytes = 1_048_576

    private static let log = Logger(subsystem: "dev.mooring", category: "hook")

    @Argument(help: "The Claude Code hook event name, such as Stop.")
    var event: String

    func execute(_ env: CLIEnvironment) async -> Int32 {
        let input = env.readInput(Self.maxInputBytes + 1)
        guard input.count <= Self.maxInputBytes else {
            Self.log.debug("Hook input over \(Self.maxInputBytes) bytes; ignored")
            return 0
        }
        guard let args = Self.args(for: event, from: input, env: env) else {
            Self.log.debug("Hook payload for \(event, privacy: .public) has no session id or isn't JSON; ignored")
            return 0
        }
        let request = Request(v: WireProtocol.version, id: env.newID(), op: .hook, args: .hook(args))
        do {
            let response = try await env.hookClient.send(request, launch: false)
            if !response.ok {
                Self.log.debug("Mooring refused hook \(event, privacy: .public): \(response.error?.message ?? "no message")")
            }
        } catch {
            Self.log.debug("Couldn't deliver hook \(event, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        return 0
    }

    /// The request arguments for a payload, or nil when it isn't a JSON object with a non-empty `session_id`.
    /// Unknown fields are ignored.
    static func args(for event: String, from input: Data, env: CLIEnvironment) -> HookArgs? {
        guard let object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
              let sessionId = object["session_id"] as? String, !sessionId.isEmpty
        else { return nil }
        let running = (object["background_tasks"] as? [Any]).map { tasks in
            tasks.filter { ($0 as? [String: Any])?["status"] as? String == "running" }.count
        }
        return HookArgs(
            event: event, sessionId: sessionId, cwd: object["cwd"] as? String,
            notificationType: object["notification_type"] as? String,
            agentID: object["agent_id"] as? String, agentType: object["agent_type"] as? String,
            runningBackgroundTasks: running,
            watchPid: ProcessTree.autoWatch(from: env.parentPID, in: env.processes)?.pid
        )
    }
}

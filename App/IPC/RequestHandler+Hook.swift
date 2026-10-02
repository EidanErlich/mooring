import AwakeKit
import Foundation
import MooringIPC

extension RequestHandler {
    /// A Claude Code hook event: asks `HookPolicy` what it means for the session's `claude-<sessionId>` lease and applies it.
    func hook(_ args: HookArgs, from caller: Caller) throws -> HookResult {
        let id = "claude-\(args.sessionId)"
        guard CallerPolicy.isValidNamedID(id) else { throw WireError(code: .badRequest, message: "Invalid session id") }
        let event = HookEvent(
            name: args.event, notificationType: args.notificationType, agentID: args.agentID, agentType: args.agentType,
            runningBackgroundTasks: args.runningBackgroundTasks, toolTimeout: args.toolTimeout
        )
        let current = now()
        let exists = engine.leases.contains { $0.id == id && $0.isLive(at: current) }
        let action = HookPolicy.action(event, settings: settings(), leaseExists: exists)
        switch action {
        case .acquire:
            try acquireSessionLease(id: id, ttl: HookPolicy.activeTTL, hook: args, from: caller)
        case .renew:
            engine.renew(id: id, ttl: HookPolicy.activeTTL)
        case .renewFor(let seconds), .setExpiry(let seconds):
            if exists {
                engine.renew(id: id, ttl: seconds)
            } else {
                try acquireSessionLease(id: id, ttl: seconds, hook: args, from: caller)
            }
        case .releaseAfter(let seconds):
            engine.shorten(id: id, to: current.addingTimeInterval(seconds))
        case .releaseNow:
            engine.release(id: id)
        case .ignore, .skipped:
            break
        }
        return HookResult(action: action.wireName)
    }

    /// Acquires the session's lease through the same path as `mooring lease acquire`, so re-acquiring merges.
    private func acquireSessionLease(id: String, ttl: TimeInterval, hook: HookArgs, from caller: Caller) throws {
        let folder = hook.cwd.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        let name = folder.isEmpty || folder == "/" ? "session" : folder
        _ = try acquire(
            AcquireArgs(
                kind: .lease, id: id, level: nil, ttl: ttl, watchPid: hook.watchPid, reason: "Claude Code · \(name)",
                agent: "Claude Code"
            ),
            from: caller
        )
    }
}

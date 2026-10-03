import AwakeKit
import Foundation
import MooringIPC

extension RequestHandler {
    /// A Claude Code hook event: asks `HookPolicy` what it means for the session's `claude-<sessionId>` lease and applies it.
    func hook(_ args: HookArgs, from caller: Caller) throws -> HookResult {
        let id = "\(Self.sessionLeasePrefix)\(args.sessionId)"
        guard CallerPolicy.isValidNamedID(id) else { throw WireError(code: .badRequest, message: "Invalid session id") }
        dropSessionLidIfOff(id)
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
            extend(id: id, by: HookPolicy.activeTTL, at: current)
        case .renewFor(let seconds):
            if exists {
                extend(id: id, by: seconds, at: current)
            } else {
                try acquireSessionLease(id: id, ttl: seconds, hook: args, from: caller)
            }
        case .setExpiry(let seconds):
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

    /// Takes lid mode off the session's lease while the settings don't allow it: before anything else, so that
    /// re-acquiring doesn't merge it back in and a renewal doesn't keep it.
    private func dropSessionLidIfOff(_ id: String) {
        let current = settings()
        guard !current.agentSessionLid || current.agentLidApproval == .never,
              let lease = engine.leases.first(where: { $0.id == id }) else { return }
        droppingLid(lease)
    }

    /// Renews to `now + ttl` unless the lease already runs longer, so a short tool event never cuts a long hold.
    private func extend(id: String, by ttl: TimeInterval, at current: Date) {
        if let expiresAt = engine.leases.first(where: { $0.id == id })?.expiresAt,
           expiresAt > current.addingTimeInterval(ttl) {
            return
        }
        engine.renew(id: id, ttl: ttl)
    }

    /// Acquires the session's lease through the same path as `mooring lease acquire`, so re-acquiring merges. It asks
    /// for lid mode while "Keep working with the lid closed" is on; a hook never waits for an approval.
    private func acquireSessionLease(id: String, ttl: TimeInterval, hook: HookArgs, from caller: Caller) throws {
        let folder = hook.cwd.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        let name = folder.isEmpty || folder == "/" ? "session \(hook.sessionId.prefix(4))" : folder
        try acquireWithoutWaiting(
            AcquireArgs(
                kind: .lease, id: id, level: settings().agentSessionLid ? "lid" : nil, ttl: ttl, watchPid: hook.watchPid,
                reason: "Claude Code · \(name)", agent: Self.claudeCode
            ),
            agent: Self.claudeCode, from: caller
        )
    }

    /// The id prefix of a Claude Code session's lease, `claude-<sessionId>`.
    static let sessionLeasePrefix = "claude-"

    /// Every hook comes from Claude Code, whatever the caller's ancestry.
    private static let claudeCode = "Claude Code"
}

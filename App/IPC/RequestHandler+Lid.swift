import AwakeKit
import Foundation
import MooringIPC

/// What an acquire that wants lid mode tells `LidApproval`.
struct LidRequest {
    let leaseID: String
    /// The agent's display name, or nil for a person.
    let agent: String?
    /// The lease the request produces will have an expiry or a watched process.
    let hasEnd: Bool
    /// The live lease the request changes, if there is one.
    let existing: Lease?
}

/// What to do with an acquire that wants lid mode.
enum LidStep: Equatable {
    case grant
    /// Acquire without lid and reply `denied` with this message.
    case refuse(String)
    /// Acquire without lid, then ask the person on this agent's behalf.
    case ask(String)
}

/// The `denied` replies (stage 2c-1 spec, "The decision").
enum LidMessage {
    static let denied = "Lid mode not approved (denied)"
    static let timeout = "Lid mode not approved (no answer in 60 s)"
    static let never = "Lid mode not approved (lid mode for agents is set to Never)"
    static let waiting = "Lid mode not approved (waiting for your answer to an earlier request)"
    static let unavailable = "Turn on notifications for Mooring in System Settings to approve lid mode"
}

extension AwakeLevel {
    var withoutLid: AwakeLevel { AwakeLevel(display: display, lid: false) }
}

extension RequestHandler {
    /// The agent the caller runs under, or nil for a person.
    func agent(of caller: Caller) -> String? {
        AgentDetection.agent(for: caller.pid, in: processes)
    }

    func liveLease(_ id: String) -> Lease? {
        let current = now()
        return engine.leases.first { $0.id == id && $0.isLive(at: current) }
    }

    /// Runs `acquire` (true: with lid as requested; false: without it) as `request` allows, asking the person when
    /// `LidApproval` says to. Returns the lease as it ends up; a refusal still acquires, then throws `denied`.
    /// A nil `request` doesn't want lid and just acquires.
    func approvingLid(_ request: LidRequest?, acquire: (Bool) throws -> Lease) async throws -> Lease {
        guard let request else { return try acquire(true) }
        switch lidStep(request) {
        case .grant:
            return try acquire(true)
        case .refuse(let message):
            _ = try acquire(false)
            throw WireError(code: .denied, message: message)
        case .ask(let agent):
            // If the CLI disconnects meanwhile, the ask still runs its course and an Allow still adds lid.
            return try await ask(agent, about: try acquire(false))
        }
    }

    func lidStep(_ request: LidRequest) -> LidStep {
        guard let agent = request.agent else { return .grant }
        let current = settings()
        let decision = LidApproval.decide(
            setting: current.agentLidApproval, agentName: agent, hasEnd: request.hasEnd,
            alwaysAllowed: current.agentLidAlwaysAllowed
        )
        switch decision {
        case .allow: return .grant
        case .refuse: return .refuse(LidMessage.never)
        case .ask:
            if request.existing?.level.lid == true { return .grant }
            // A denial lasts for that lease's lifetime: one that ended (or was replaced) is asked afresh.
            deniedLid = deniedLid.filter { id, created in liveLease(id)?.createdAt == created }
            if let existing = request.existing, deniedLid[existing.id] == existing.createdAt {
                return .refuse(LidMessage.denied)
            }
            if approver.pending.contains(request.leaseID) { return .refuse(LidMessage.waiting) }
            return .ask(agent)
        }
    }

    /// Asks the person whether `agent` may add lid mode to `lease`, then applies the answer: lid on Allow, if the
    /// lease is still live; otherwise a `denied` error (or `notFound` when the lease ended while waiting).
    func ask(_ agent: String, about lease: Lease) async throws -> Lease {
        let answer = await approver.ask(leaseID: lease.id, agent: agent, body: approvalBody(lease))
        switch answer {
        case .allowOnce, .alwaysAllow:
            if answer == .alwaysAllow { alwaysAllow(agent) }
            guard let current = liveLease(lease.id) else {
                throw WireError(code: .notFound, message: "\(lease.id) ended before lid mode was approved")
            }
            engine.setLevel(current.level.union(AwakeLevel(display: false, lid: true)), forLease: current.id)
            return liveLease(lease.id) ?? current
        case .deny:
            if let current = liveLease(lease.id) { deniedLid[current.id] = current.createdAt }
            throw WireError(code: .denied, message: LidMessage.denied)
        case .timeout:
            throw WireError(code: .denied, message: LidMessage.timeout)
        case .unavailable:
            throw WireError(code: .denied, message: LidMessage.unavailable)
        }
    }

    /// "<reason> · <with no end time | for 30m | while <process> runs>"; the center adds the agent's name.
    private func approvalBody(_ lease: Lease) -> String {
        let end = if let pid = lease.watch?.pid {
            "while \(processes.entry(pid)?.name ?? "pid \(pid)") runs"
        } else if let expiry = lease.expiresAt {
            "for \(DurationText.remaining(expiry.timeIntervalSince(now())))"
        } else {
            "with no end time"
        }
        return "\(lease.reason) · \(end)"
    }

    private func alwaysAllow(_ agent: String) {
        updateSettings { settings in
            if !settings.agentLidAlwaysAllowed.contains(agent) { settings.agentLidAlwaysAllowed.append(agent) }
        }
    }
}

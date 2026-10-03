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
    /// `existing` already has lid mode that this request can't widen, so there is nothing to ask: for a named lease
    /// any lid (the cap bounds it); for `on`, only an open-ended lid session.
    let existingCovers: Bool
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
    static let changed = "Lid mode not approved (the request changed while you were deciding)"
    /// How long a Deny holds before the agent may ask about the same lease again.
    static let denialLasts: TimeInterval = 15 * 60

    /// The reply to an ask refused because the person denied it until `until`.
    static func deniedUntil(_ until: Date) -> String {
        "Lid mode not approved (you denied it; ask again after \(until.formatted(date: .omitted, time: .shortened)))"
    }
}

extension AwakeLevel {
    var withoutLid: AwakeLevel { AwakeLevel(display: display, lid: false) }
}

extension RequestHandler {
    /// The agent the caller runs under, with that agent process's pid, or nil for a person. An MCP client's process
    /// is the caller itself. An in-app forced agent has no agent process (nil pid), so any watch counts as its
    /// lease's end, as for a hook; the app never sets one.
    func agentProcess(of caller: Caller) -> (name: String, pid: Int32?)? {
        switch caller.identity {
        case .detect: AgentDetection.agentProcess(for: caller.pid, in: processes).map { ($0.name, $0.pid) }
        case .agent(let name): (name, nil)
        case .client(let name): (name, caller.pid)
        case .person: nil
        }
    }

    /// Whether a lease an agent asks for ends: by its expiry, or by a watch on the agent's own process or one below
    /// it. Watching anything else (launchd, the Terminal, the agent's parents) is no end. `agentPID` nil (a hook,
    /// which comes from Claude Code whatever its ancestry) takes any watch as an end.
    func hasEnd(ttl: TimeInterval?, watching watched: Int32?, agentPID: Int32?) -> Bool {
        guard ttl == nil, let watched, let agentPID else { return true }
        return AgentDetection.descends(watched, from: agentPID, in: processes)
    }

    func liveLease(_ id: String) -> Lease? {
        let current = now()
        return engine.leases.first { $0.id == id && $0.isLive(at: current) }
    }

    /// Runs `acquire` (true: with lid as requested; false: without it) as `request` allows, asking the person when
    /// `LidApproval` says to. Returns the lease as it ends up; a refusal still acquires, then throws `denied`.
    /// A nil `request` doesn't want lid and just acquires. `reason` leads the notification instead of the lease's own.
    func approvingLid(
        _ request: LidRequest?, reason: String? = nil, acquire: (Bool) throws -> Lease
    ) async throws -> Lease {
        guard let request else { return try acquire(true) }
        switch lidStep(request) {
        case .grant:
            return noteGrant(try acquire(true), for: request)
        case .refuse(let message):
            // Acquiring again merges in the existing level, so lid is taken off afterwards: the reply is the outcome.
            droppingLid(try acquire(false))
            throw WireError(code: .denied, message: message)
        case .ask(let agent):
            // If the CLI disconnects meanwhile, the ask still runs its course and an Allow still adds lid.
            return try await ask(agent, about: droppingLid(try acquire(false)), reason: reason)
        }
    }

    /// Records who `lease`'s lid mode belongs to after `request` was granted. Lid an agent added is recorded, so the
    /// settings can take it back; a person's request, or lid a person's lease already had, is never recorded.
    @discardableResult
    func noteGrant(_ lease: Lease, for request: LidRequest) -> Lease {
        agentLid = agentLid.filter { id, created in engine.leases.first { $0.id == id }?.createdAt == created }
        guard request.agent != nil else {
            agentLid[lease.id] = nil
            return lease
        }
        let personsLid = request.existing.map { $0.level.lid && agentLid[$0.id] != $0.createdAt } ?? false
        if lease.level.lid && !personsLid { agentLid[lease.id] = lease.createdAt }
        return lease
    }

    /// `lease` at its level without lid mode, and no longer recorded as an agent's.
    @discardableResult
    func droppingLid(_ lease: Lease) -> Lease {
        agentLid[lease.id] = nil
        guard lease.level.lid else { return lease }
        engine.setLevel(lease.level.withoutLid, forLease: lease.id)
        return engine.leases.first { $0.id == lease.id } ?? lease
    }

    /// Takes lid mode back from live leases that got it on an agent's behalf once the settings no longer allow it:
    /// Never takes it from every agent lease, "Keep working with the lid closed" off from Claude Code sessions.
    func applyLidSettings() {
        let current = settings()
        let never = current.agentLidApproval == .never
        guard never || !current.agentSessionLid else { return }
        for (id, created) in agentLid where never || id.hasPrefix(Self.sessionLeasePrefix) {
            guard let lease = engine.leases.first(where: { $0.id == id }), lease.createdAt == created else {
                agentLid[id] = nil
                continue
            }
            droppingLid(lease)
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
            if request.existingCovers { return .grant }
            // A denial lasts `denialLasts`, or until its lease ends (or is replaced): then it's asked afresh.
            let time = now()
            deniedLid = deniedLid.filter { id, denial in
                liveLease(id)?.createdAt == denial.created && time < denial.until
            }
            if let existing = request.existing, let denial = deniedLid[existing.id],
               denial.created == existing.createdAt {
                return .refuse(LidMessage.deniedUntil(denial.until))
            }
            if asking.contains(request.leaseID) || approver.pending.contains(request.leaseID) {
                return .refuse(LidMessage.waiting)
            }
            return .ask(agent)
        }
    }

    /// Asks the person whether `agent` may add lid mode to `lease`, then applies the answer: lid on Allow, if the
    /// lease is still the one they were told about; otherwise a `denied` error (or `notFound` when it ended). The
    /// notification gives `reason`, else the lease's own.
    func ask(_ agent: String, about lease: Lease, reason: String? = nil) async throws -> Lease {
        // Marked before the first suspension, so a second request for this lease is refused rather than asked again.
        asking.insert(lease.id)
        defer { asking.remove(lease.id) }
        let answer = await approver.ask(leaseID: lease.id, agent: agent, body: approvalBody(lease, reason: reason))
        let current = liveLease(lease.id)
        switch answer {
        case .allowOnce, .alwaysAllow:
            if answer == .alwaysAllow { alwaysAllow(agent) }
            guard let current else {
                throw WireError(code: .notFound, message: "\(lease.id) ended before lid mode was approved")
            }
            guard Self.endsAsTold(current, asked: lease) else { throw WireError(code: .denied, message: LidMessage.changed) }
            engine.setLevel(current.level.union(AwakeLevel(display: false, lid: true)), forLease: current.id)
            agentLid[current.id] = current.createdAt
            return liveLease(lease.id) ?? current
        case .deny:
            if let current, current.createdAt == lease.createdAt {
                deniedLid[current.id] = (current.createdAt, now().addingTimeInterval(LidMessage.denialLasts))
            }
            throw WireError(code: .denied, message: LidMessage.denied)
        case .timeout:
            throw WireError(code: .denied, message: LidMessage.timeout)
        case .unavailable:
            throw WireError(code: .denied, message: LidMessage.unavailable)
        }
    }

    /// `current` is the lease the person was asked about, in the same lifetime, and it ends no later than the
    /// notification said: while the same process runs, or by the expiry shown. "With no end time" can't get weaker.
    private static func endsAsTold(_ current: Lease, asked: Lease) -> Bool {
        guard current.createdAt == asked.createdAt else { return false }
        // The body names the process when there is one, and that is the end the person approved.
        if let pid = asked.watch?.pid { return current.watch?.pid == pid }
        guard let expiry = asked.expiresAt else { return true }
        return current.expiresAt.map { $0 <= expiry } ?? false
    }

    /// "<reason> · <with no end time | for 30m | while <process> runs>"; the center adds the agent's name.
    private func approvalBody(_ lease: Lease, reason: String?) -> String {
        let end = if let pid = lease.watch?.pid {
            "while \(processes.entry(pid)?.name ?? "pid \(pid)") runs"
        } else if let expiry = lease.expiresAt {
            "for \(DurationText.remaining(expiry.timeIntervalSince(now())))"
        } else {
            "with no end time"
        }
        return "\(reason ?? lease.reason) · \(end)"
    }

    private func alwaysAllow(_ agent: String) {
        updateSettings { settings in
            if !settings.agentLidAlwaysAllowed.contains(agent) { settings.agentLidAlwaysAllowed.append(agent) }
        }
    }
}

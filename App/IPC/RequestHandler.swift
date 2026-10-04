import AwakeKit
import Foundation
import MooringIPC
import os

/// Who a caller is taken to be: found from its process ancestry, or given by the path the request came in on.
enum CallerIdentity: Sendable, Equatable {
    /// Agent detection over the caller's ancestry decides.
    case detect
    /// An agent with this display name, whatever the ancestry: an in-app intent naming one. It has no agent process.
    case agent(String)
    /// An MCP client, by display name, from the request's `client`: an agent whose own process is the caller (the
    /// MCP server), so only a watch on that process or one below it counts as an end.
    case client(String)
    /// A person, whatever the ancestry.
    case person
}

/// The peer on the other end of a socket connection, as the kernel reports it, and who it is taken to be.
struct Caller: Sendable {
    let uid: uid_t
    let pid: Int32
    var identity: CallerIdentity = .detect
}

extension LeaseInfo {
    init(_ lease: Lease, pendingApproval: Bool = false) {
        let kind: String
        switch lease.owner {
        case .menu: kind = "menu"
        case .cli: kind = "cli"
        case .agent: kind = "agent"
        case .mcp: kind = "mcp"
        }
        self.init(
            id: lease.id, owner: OwnerInfo(kind: kind, name: LeaseText.owner(lease.owner)), reason: lease.reason,
            level: WireText.levelName(display: lease.level.display, lid: lease.level.lid),
            expiresAt: lease.expiresAt, watchPid: lease.watch?.pid, ttl: lease.ttl,
            pendingApproval: pendingApproval
        )
    }
}

/// Turns a decoded CLI request into engine calls, through `CallerPolicy` and `LidApproval`, and builds the reply.
@MainActor
final class RequestHandler {
    let engine: AwakeEngine
    let settings: @MainActor () -> AwakeSettings
    let helperStatus: @MainActor () -> String
    let readHelperSleepDisabled: @MainActor () async -> Bool?
    let now: @MainActor () -> Date
    /// The process ancestry agent detection walks.
    let processes: any ProcessTable
    let approver: any LidApproving
    let updateSettings: @MainActor ((inout AwakeSettings) -> Void) -> Void
    let notificationStatus: @MainActor () async -> String?
    /// Posts `notify`'s notifications.
    let poster: any NotificationPosting
    /// Leases whose lid ask was denied, by id, with the creation time of the lease that was denied and when the
    /// denial ends: it isn't asked again in that lifetime until then.
    var deniedLid: [String: (created: Date, until: Date)] = [:]
    /// Leases with an ask under way, from before its first suspension until it's answered: at most one ask per lease.
    var asking: Set<String> = []
    /// Leases given lid mode on an agent's behalf, with their creation time, so the settings can take it back.
    var agentLid: [String: Date] = [:]
    /// When each caller last posted with `notify`, by name (and by `pid-<pid>` for an MCP client), for the rate limit.
    var lastNotified: [String: Date] = [:]
    private let log = Logger(subsystem: "dev.mooring", category: "ipc")

    init(
        engine: AwakeEngine, settings: @escaping @MainActor () -> AwakeSettings,
        helperStatus: @escaping @MainActor () -> String, readHelperSleepDisabled: @escaping @MainActor () async -> Bool?,
        now: @escaping @MainActor () -> Date = { Date() }, processes: any ProcessTable = SystemProcessTable(),
        approver: any LidApproving, updateSettings: @escaping @MainActor ((inout AwakeSettings) -> Void) -> Void,
        notificationStatus: @escaping @MainActor () async -> String?, poster: any NotificationPosting
    ) {
        self.engine = engine
        self.settings = settings
        self.helperStatus = helperStatus
        self.readHelperSleepDisabled = readHelperSleepDisabled
        self.now = now
        self.processes = processes
        self.approver = approver
        self.updateSettings = updateSettings
        self.notificationStatus = notificationStatus
        self.poster = poster
    }

    func handle(_ request: Request, from caller: Caller) async -> Response {
        do {
            switch request.args {
            case .acquire(let args) where args.kind == .on:
                return .success(id: request.id, .acquire(try await turnOn(args, from: identified(caller, client: args.client))))
            case .acquire(let args):
                return .success(id: request.id, .acquire(try await acquire(args, from: identified(caller, client: args.client))))
            case .renew(let args): return .success(id: request.id, .renew(try renew(args)))
            case .release(let args): return .success(id: request.id, .release(try release(args)))
            case .status: return .success(id: request.id, .status(await status()))
            case .hook(let args): return .success(id: request.id, .hook(try hook(args, from: caller)))
            case .notify(let args):
                return .success(id: request.id, .notify(try await notify(args, from: identified(caller, client: args.client))))
            case .winList, .winArrange, .winUndo, .winLayout:
                throw WireError(code: .badRequest, message: "\(request.op.rawValue) is not supported yet")
            }
        } catch {
            let wire = error as? WireError ?? WireError(code: .internal, message: "Internal error")
            let operation = String(describing: request.op)
            log.notice("\(operation, privacy: .public) from pid \(caller.pid) failed: \(wire.message, privacy: .public)")
            return .failure(id: request.id, wire.code, wire.message)
        }
    }

    // MARK: - acquire

    /// What one acquire asks for once the request's kind has filled in its defaults.
    private struct Plan {
        let id: String
        let owner: LeaseOwner
        let reason: String
        let level: AwakeLevel
        let ttl: TimeInterval?
        let watchPID: Int32?
        let caller: CallerKind

        /// This plan for a named lease that already exists, so that acquiring it again never weakens it: it keeps the
        /// existing watch, level, reason and owner unless the request gives its own (a level only ever adds to the old one).
        func merged(with existing: Lease, args: AcquireArgs) -> Plan {
            let ownerGiven = args.client != nil || (args.agent.map(CallerPolicy.cleanAgentName).map { !$0.isEmpty } ?? false)
            return Plan(
                id: id, owner: ownerGiven ? owner : existing.owner,
                reason: reasonGiven(args) ? reason : existing.reason,
                level: level.union(existing.level), ttl: ttl, watchPID: watchPID ?? existing.watch?.pid, caller: caller
            )
        }

        /// This plan at its level without lid mode.
        func withoutLid() -> Plan {
            Plan(id: id, owner: owner, reason: reason, level: level.withoutLid, ttl: ttl, watchPID: watchPID, caller: caller)
        }

        private func reasonGiven(_ args: AcquireArgs) -> Bool {
            args.reason.map(CallerPolicy.cleanReason).map { !$0.isEmpty } ?? false
        }
    }

    /// The duration to grant when a named lease is acquired again: `granted`, unless the lease already runs longer
    /// (a lease with no expiry keeps none), within the cap on named leases.
    private static func keepingLater(_ granted: TimeInterval?, of existing: Lease, at current: Date) -> TimeInterval? {
        guard let expiry = existing.expiresAt else { return nil }
        let remaining = expiry.timeIntervalSince(current)
        return granted.map { min(max($0, remaining), CallerPolicy.maxNamedLease) }
    }

    /// `anchor` and `lease acquire`. A request for lid mode goes through `LidApproval` first, and may wait for the person.
    private func acquire(_ args: AcquireArgs, from caller: Caller) async throws -> MooringIPC.AcquireResult {
        let plan = try plan(for: args, from: caller)
        var clamped = false
        let agent = agentProcess(of: caller)
        let request = plan.level.lid ? lidRequest(for: plan, agent: agent?.name, agentPID: agent?.pid) : nil
        let lease = try await approvingLid(request) { withLid in
            let granted = try grant(args, plan: withLid ? plan : plan.withoutLid())
            clamped = granted.clamped
            return granted.lease
        }
        if let message = guardrailMessage(holdingBack: lease.level) {
            throw WireError(code: .guardrail, message: Self.holdNotice(message, kind: args.kind, id: plan.id, mcp: args.client != nil))
        }
        return MooringIPC.AcquireResult(lease: LeaseInfo(lease), clamped: clamped)
    }

    /// The hook's acquire, by the same rules but never waiting: Claude gives a hook 2 s. When the person must be
    /// asked, the lease starts without lid and the ask runs in the background, adding lid on Allow.
    func acquireWithoutWaiting(_ args: AcquireArgs, agent: String, from caller: Caller) throws {
        let plan = try plan(for: args, from: caller)
        let request = plan.level.lid ? lidRequest(for: plan, agent: agent, agentPID: nil) : nil
        let step = request.map(lidStep) ?? .grant
        var lease = try grant(args, plan: step == .grant ? plan : plan.withoutLid()).lease
        if let request { lease = step == .grant ? noteGrant(lease, for: request) : droppingLid(lease) }
        if case .ask(let agent) = step {
            // Marked now, not when the task starts, so the session's next hook event isn't asked again.
            asking.insert(lease.id)
            Task { @MainActor in _ = try? await self.ask(agent, about: lease) }
        }
        if let message = guardrailMessage(holdingBack: lease.level) {
            throw WireError(code: .guardrail, message: Self.holdNotice(message, kind: args.kind, id: plan.id, mcp: args.client != nil))
        }
    }

    /// A named lease or anchor ends by its `--ttl`, or by its watch when that is on the agent's own processes.
    private func lidRequest(for plan: Plan, agent: String?, agentPID: Int32?) -> LidRequest {
        let existing = liveLease(plan.id), ends = hasEnd(ttl: plan.ttl, watching: plan.watchPID, agentPID: agentPID)
        return LidRequest(leaseID: plan.id, agent: agent, hasEnd: ends, existing: existing, existingCovers: existing?.level.lid == true)
    }

    /// Creates or updates the lease `plan` describes, merging with a named lease that exists.
    private func grant(_ args: AcquireArgs, plan: Plan) throws -> (lease: Lease, clamped: Bool) {
        var plan = plan
        let current = now()
        let existing = args.kind == .lease ? engine.leases.first { $0.id == plan.id } : nil
        if let existing { plan = plan.merged(with: existing, args: args) }
        let requested = try grantedDuration(
            for: plan, liveLeases: engine.leases.filter { $0.isLive(at: current) }.count, exists: existing != nil
        )
        var granted = requested
        var renewLength = requested
        if let existing {
            granted = Self.keepingLater(requested, of: existing, at: current)
            // The length `renew` reuses is the longest asked for, not the time left, so repeated acquires don't shrink it.
            renewLength = granted.map { _ in min(max(existing.ttl ?? 0, requested ?? 0), CallerPolicy.maxNamedLease) }
        }
        guard let outcome = engine.acquire(
            id: plan.id, owner: plan.owner, reason: plan.reason, level: plan.level, duration: granted,
            watchPID: plan.watchPID, ttl: renewLength
        ) else {
            throw plan.watchPID.map { WireError(code: .badRequest, message: "Process \($0) isn't running") }
                ?? WireError(code: .internal, message: "Couldn't create the lease")
        }
        let cutShort = plan.ttl.map { requested in granted.map { $0 < requested } ?? false } ?? false
        return (outcome.lease, outcome.wasClamped || cutShort)
    }

    /// `mooring on`: the menu's On switch. With no flags it leaves a running session alone (and asks nothing); with
    /// `--for` or `--level` it replaces the session (and any picked apps), as picking a duration does.
    private func turnOn(_ args: AcquireArgs, from caller: Caller) async throws -> MooringIPC.AcquireResult {
        let ttl = try positive(args.ttl)
        let level = try args.level.map(parseLevel)
        let session = engine.menuLease ?? engine.sessionApps.first
        let lease: Lease
        if ttl == nil && level == nil && args.untilOff != true, let session {
            lease = session
        } else {
            let current = now()
            _ = try grantedDuration(
                for: Plan(
                    id: AwakeEngine.menuLeaseID, owner: .menu, reason: AwakeEngine.menuReason, level: level ?? .system,
                    ttl: ttl, watchPID: nil, caller: .trusted
                ),
                liveLeases: engine.leases.filter { $0.isLive(at: current) }.count, exists: engine.hasMenuSession
            )
            let defaults = settings()
            let requested = level ?? engine.sessionLevel ?? defaults.clickLevel
            // `untilOff` asks for no end, which the click duration would otherwise fill in.
            let duration = ttl ?? (args.untilOff == true ? nil : defaults.clickDuration)
            let existing = session.flatMap { liveLease($0.id) }
            // `on` replaces the session, and may drop its end, so only an open-ended lid session already covers it.
            let covers = existing.map { $0.level.lid && $0.expiresAt == nil && $0.watch == nil } ?? false
            let request = LidRequest(
                leaseID: AwakeEngine.menuLeaseID, agent: agentProcess(of: caller)?.name, hasEnd: duration != nil,
                existing: existing, existingCovers: covers
            )
            // The menu session keeps its own reason; the person is told what the agent ran.
            lease = try await approvingLid(requested.lid ? request : nil, reason: cleaned(args.reason) ?? "mooring on") { withLid in
                engine.turnOnMenu(duration: duration, level: withLid ? requested : requested.withoutLid)
                guard let lease = engine.menuLease else { throw WireError(code: .internal, message: "Couldn't turn on") }
                return lease
            }
        }
        if let held = heldSuspension(holdingBack: lease.level) {
            let notice = caller.identity == .person
                ? personHoldNotice(held)
                : Self.holdNotice(Self.guardrailMessage(held), kind: .on, id: lease.id, mcp: false)
            throw WireError(code: .guardrail, message: notice)
        }
        return MooringIPC.AcquireResult(lease: LeaseInfo(lease), clamped: (ttl ?? 0) > AwakeEngine.maxLeaseLength)
    }

    private func plan(for args: AcquireArgs, from caller: Caller) throws -> Plan {
        let ttl = try positive(args.ttl)
        let level = try args.level.map(parseLevel)
        let owner = mcpOwner(args.client)
            ?? args.agent.map(CallerPolicy.cleanAgentName).flatMap { $0.isEmpty ? nil : LeaseOwner.agent(name: $0) }
            ?? .cli(pid: caller.pid)
        switch args.kind {
        case .on:
            throw WireError(code: .internal, message: "On is not a named lease")
        case .anchor:
            guard let pid = args.watchPid else { throw WireError(code: .badRequest, message: "Missing --pid") }
            try checkMCPPrefix("anchor-\(pid)", client: args.client)
            return Plan(
                id: "anchor-\(pid)", owner: owner, reason: cleaned(args.reason) ?? "pid \(pid)",
                level: level ?? .system, ttl: ttl, watchPID: pid, caller: .trusted
            )
        case .lease:
            guard let id = args.id else { throw WireError(code: .badRequest, message: "Missing lease id") }
            try checkMCPPrefix(id, client: args.client)
            return Plan(
                id: id, owner: owner, reason: cleaned(args.reason) ?? id,
                level: level ?? .system, ttl: ttl, watchPID: args.watchPid, caller: .named
            )
        }
    }

    private func grantedDuration(for plan: Plan, liveLeases: Int, exists: Bool) throws -> TimeInterval? {
        let result = CallerPolicy.checkAcquire(
            kind: plan.caller, id: plan.id, level: plan.level, ttl: plan.ttl, watched: plan.watchPID != nil,
            liveLeaseCount: liveLeases, exists: exists
        )
        switch result {
        case .success(let granted): return granted
        case .failure(.badRequest(let message)): throw WireError(code: .badRequest, message: message)
        case .failure(.denied(let message)): throw WireError(code: .denied, message: message)
        }
    }

    /// The guardrail `message` plus what the caller must know: the lease exists even though the
    /// reply is a refusal, so it applies later and, for `on` and `lease`, still needs ending. An MCP client
    /// (`mcp`) ends it with its `release_awake` tool, not the CLI.
    private static func holdNotice(_ message: String, kind: AcquireKind, id: String, mcp: Bool) -> String {
        if mcp { return "\(message). The lease is held and resumes when that clears; call release_awake to end it." }
        return switch kind {
        case .lease: "\(message). Lease \(id) is held and applies when that clears; run `mooring lease release \(id)` to end it."
        case .on: "\(message). Mooring is on and applies when that clears; run `mooring off` to end it."
        case .anchor: "\(message). The anchor applies when that clears."
        }
    }

    /// The guardrail that holds back a lease at `level`, if one does. Low battery pauses everything; the others
    /// pause only lid mode.
    private func heldSuspension(holdingBack level: AwakeLevel) -> Suspension? {
        let active = engine.state.suspensions
        if active.contains(.lowBatteryAll) { return .lowBatteryAll }
        guard level.lid else { return nil }
        return [Suspension.lowBatteryLid, .thermal, .lidNeedsAC].first { active.contains($0) }
    }

    private func guardrailMessage(holdingBack level: AwakeLevel) -> String? {
        heldSuspension(holdingBack: level).map(Self.guardrailMessage)
    }

    private static func guardrailMessage(_ suspension: Suspension) -> String {
        switch suspension {
        case .lowBatteryAll: "Paused: battery low"
        case .lowBatteryLid: "Lid mode paused: battery low"
        case .thermal: "Lid mode paused: Mac too warm"
        case .lidNeedsAC: "Lid mode paused: needs power"
        }
    }

    /// What a person (the Shortcuts actions) is told when `suspension` holds their session back: the title of the
    /// notification that guardrail posts, without the CLI advice to end it.
    private func personHoldNotice(_ suspension: Suspension) -> String {
        let title = GuardrailNotifier.message(for: suspension, settings: settings()).title
        return "\(title). Mooring is on and starts when that clears."
    }
}

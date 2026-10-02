import AwakeKit
import Foundation
import MooringIPC
import os

/// The peer on the other end of a socket connection, as the kernel reports it.
struct Caller: Sendable {
    let uid: uid_t
    let pid: Int32
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
    private let helperStatus: @MainActor () -> String
    private let readHelperSleepDisabled: @MainActor () async -> Bool?
    let now: @MainActor () -> Date
    /// The process ancestry agent detection walks.
    let processes: any ProcessTable
    let approver: any LidApproving
    let updateSettings: @MainActor ((inout AwakeSettings) -> Void) -> Void
    private let notificationStatus: @MainActor () async -> String?
    /// Leases whose lid ask was denied, by id, with the creation time of the lease that was denied: it isn't asked
    /// again in that lifetime (stage 2c-1 spec).
    var deniedLid: [String: Date] = [:]
    /// Leases with an ask under way, from before its first suspension until it's answered: at most one ask per lease.
    var asking: Set<String> = []
    /// Leases given lid mode on an agent's behalf, with their creation time, so the settings can take it back.
    var agentLid: [String: Date] = [:]
    private let log = Logger(subsystem: "dev.mooring", category: "ipc")
    /// The id `mooring on` used before it became the menu's On switch.
    private static let legacyCLILeaseID = "cli"

    init(
        engine: AwakeEngine, settings: @escaping @MainActor () -> AwakeSettings,
        helperStatus: @escaping @MainActor () -> String, readHelperSleepDisabled: @escaping @MainActor () async -> Bool?,
        now: @escaping @MainActor () -> Date = { Date() }, processes: any ProcessTable = SystemProcessTable(),
        approver: any LidApproving, updateSettings: @escaping @MainActor ((inout AwakeSettings) -> Void) -> Void,
        notificationStatus: @escaping @MainActor () async -> String?
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
    }

    func handle(_ request: Request, from caller: Caller) async -> Response {
        do {
            switch request.args {
            case .acquire(let args) where args.kind == .on:
                return .success(id: request.id, .acquire(try await turnOn(args, from: caller)))
            case .acquire(let args): return .success(id: request.id, .acquire(try await acquire(args, from: caller)))
            case .renew(let args): return .success(id: request.id, .renew(try renew(args)))
            case .release(let args): return .success(id: request.id, .release(try release(args)))
            case .status: return .success(id: request.id, .status(await status()))
            case .hook(let args): return .success(id: request.id, .hook(try hook(args, from: caller)))
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
            let ownerGiven = args.agent.map(CallerPolicy.cleanAgentName).map { !$0.isEmpty } ?? false
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
        let lease = try await approvingLid(plan.level.lid ? lidRequest(for: plan, agent: agent(of: caller)) : nil) { withLid in
            let granted = try grant(args, plan: withLid ? plan : plan.withoutLid())
            clamped = granted.clamped
            return granted.lease
        }
        if let message = guardrailMessage(holdingBack: lease.level) {
            throw WireError(code: .guardrail, message: Self.holdNotice(message, kind: args.kind, id: plan.id))
        }
        return MooringIPC.AcquireResult(lease: LeaseInfo(lease), clamped: clamped)
    }

    /// The hook's acquire, by the same rules but never waiting: Claude gives a hook 2 s. When the person must be
    /// asked, the lease starts without lid and the ask runs in the background, adding lid on Allow.
    func acquireWithoutWaiting(_ args: AcquireArgs, agent: String, from caller: Caller) throws {
        let plan = try plan(for: args, from: caller)
        let request = plan.level.lid ? lidRequest(for: plan, agent: agent) : nil
        let step = request.map(lidStep) ?? .grant
        var lease = try grant(args, plan: step == .grant ? plan : plan.withoutLid()).lease
        if let request { lease = step == .grant ? noteGrant(lease, for: request) : droppingLid(lease) }
        if case .ask(let agent) = step {
            // Marked now, not when the task starts, so the session's next hook event isn't asked again.
            asking.insert(lease.id)
            Task { @MainActor in _ = try? await self.ask(agent, about: lease) }
        }
        if let message = guardrailMessage(holdingBack: lease.level) {
            throw WireError(code: .guardrail, message: Self.holdNotice(message, kind: args.kind, id: plan.id))
        }
    }

    /// Named leases always end: the cap bounds them, and an anchor watches its process.
    private func lidRequest(for plan: Plan, agent: String?) -> LidRequest {
        let existing = liveLease(plan.id)
        return LidRequest(
            leaseID: plan.id, agent: agent, hasEnd: true, existing: existing, existingCovers: existing?.level.lid == true
        )
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
        if ttl == nil && level == nil, let session {
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
            let duration = ttl ?? defaults.clickDuration
            let existing = session.flatMap { liveLease($0.id) }
            // `on` replaces the session, and may drop its end, so only an open-ended lid session already covers it.
            let covers = existing.map { $0.level.lid && $0.expiresAt == nil && $0.watch == nil } ?? false
            let request = LidRequest(
                leaseID: AwakeEngine.menuLeaseID, agent: agent(of: caller), hasEnd: duration != nil,
                existing: existing, existingCovers: covers
            )
            lease = try await approvingLid(requested.lid ? request : nil) { withLid in
                engine.turnOnMenu(duration: duration, level: withLid ? requested : requested.withoutLid)
                guard let lease = engine.menuLease else { throw WireError(code: .internal, message: "Couldn't turn on") }
                return lease
            }
        }
        if let message = guardrailMessage(holdingBack: lease.level) {
            throw WireError(code: .guardrail, message: Self.holdNotice(message, kind: .on, id: lease.id))
        }
        return MooringIPC.AcquireResult(lease: LeaseInfo(lease), clamped: (ttl ?? 0) > AwakeEngine.maxLeaseLength)
    }

    private func plan(for args: AcquireArgs, from caller: Caller) throws -> Plan {
        let ttl = try positive(args.ttl)
        let level = try args.level.map(parseLevel)
        let owner = args.agent.map(CallerPolicy.cleanAgentName).flatMap { $0.isEmpty ? nil : LeaseOwner.agent(name: $0) }
            ?? .cli(pid: caller.pid)
        switch args.kind {
        case .on:
            throw WireError(code: .internal, message: "On is not a named lease")
        case .anchor:
            guard let pid = args.watchPid else { throw WireError(code: .badRequest, message: "Missing --pid") }
            return Plan(
                id: "anchor-\(pid)", owner: owner, reason: cleaned(args.reason) ?? "pid \(pid)",
                level: level ?? .system, ttl: ttl, watchPID: pid, caller: .trusted
            )
        case .lease:
            guard let id = args.id else { throw WireError(code: .badRequest, message: "Missing lease id") }
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
    /// reply is a refusal, so it applies later and, for `on` and `lease`, still needs ending.
    private static func holdNotice(_ message: String, kind: AcquireKind, id: String) -> String {
        switch kind {
        case .lease: "\(message). Lease \(id) is held and applies when that clears; run `mooring lease release \(id)` to end it."
        case .on: "\(message). Mooring is on and applies when that clears; run `mooring off` to end it."
        case .anchor: "\(message). The anchor applies when that clears."
        }
    }

    /// Why a guardrail holds back a lease at `level`, if one does. Low battery pauses everything;
    /// the others pause only lid mode.
    private func guardrailMessage(holdingBack level: AwakeLevel) -> String? {
        let active = engine.state.suspensions
        if active.contains(.lowBatteryAll) { return "Paused: battery low" }
        guard level.lid else { return nil }
        if active.contains(.lowBatteryLid) { return "Lid mode paused: battery low" }
        if active.contains(.thermal) { return "Lid mode paused: Mac too warm" }
        if active.contains(.lidNeedsAC) { return "Lid mode paused: needs power" }
        return nil
    }

}

extension RequestHandler {
    // MARK: - renew and release

    private func renew(_ args: RenewArgs) throws -> LeaseInfo {
        let ttl = try positive(args.ttl)
        try requireUnreserved(args.id)
        guard engine.leases.contains(where: { $0.id == args.id }) else {
            throw WireError(code: .notFound, message: "No lease \(args.id); acquire it again")
        }
        guard let lease = engine.renew(id: args.id, ttl: ttl.map { min($0, CallerPolicy.maxNamedLease) }) else {
            throw WireError(code: .internal, message: "Couldn't renew \(args.id)")
        }
        return LeaseInfo(lease)
    }

    private func release(_ args: ReleaseArgs) throws -> ReleaseResult {
        let after = try positive(args.after)
        switch args.kind {
        case .off:
            return ReleaseResult(released: turnOff())
        case .lease:
            guard let id = args.id else { throw WireError(code: .badRequest, message: "Missing lease id") }
            try requireUnreserved(id)
            guard engine.leases.contains(where: { $0.id == id }) else { return ReleaseResult(released: false) }
            if let after {
                engine.shorten(id: id, to: now().addingTimeInterval(after))
            } else {
                engine.release(id: id)
            }
            return ReleaseResult(released: true)
        }
    }

    /// `mooring off`: ends the menu session, as the menu's On switch does, and a `cli` lease an
    /// earlier build may have left. Agent leases and anchors stay.
    private func turnOff() -> Bool {
        var ended = engine.hasMenuSession
        engine.endMenuSession()
        if engine.leases.contains(where: { $0.id == Self.legacyCLILeaseID }) {
            engine.release(id: Self.legacyCLILeaseID)
            ended = true
        }
        return ended
    }

    // MARK: - status

    private func status() async -> StatusResult {
        // The helper and notification reads suspend, so take them first and read the engine in one synchronous stretch.
        let helperSleepDisabled = await readHelperSleepDisabled()
        let notifications = await notificationStatus()
        let current = now()
        let state = engine.state
        let live = engine.leases.filter { $0.isLive(at: current) }
        return StatusResult(
            summary: StatusLine.text(leases: engine.leases, state: state, now: current),
            effective: LevelInfo(system: state.systemAssertion, display: state.displayAssertion, lid: state.lidSleepDisabled),
            systemAssertion: state.systemAssertion, displayAssertion: state.displayAssertion,
            lidSleepDisabled: state.lidSleepDisabled, helperSleepDisabled: helperSleepDisabled,
            wantsLid: engine.wantsLid,
            leases: live.map { LeaseInfo($0, pendingApproval: asking.contains($0.id) || approver.pending.contains($0.id)) },
            power: PowerInfo(onAC: engine.power.onAC, batteryPercent: engine.power.batteryPercent),
            thermal: Self.thermalName(engine.thermal), lidClosed: engine.lidClosed, helper: helperStatus(),
            suspensions: state.suspensions.map { String(describing: $0) }.sorted(),
            notifications: notifications, agentLidApproval: settings().agentLidApproval.rawValue
        )
    }

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "nominal"
        }
    }

    // MARK: - Validation

    /// `seconds` unchanged, or a bad request when it isn't a positive, finite length of time.
    private func positive(_ seconds: Double?) throws -> Double? {
        guard let seconds else { return nil }
        guard seconds.isFinite, seconds > 0 else { throw WireError(code: .badRequest, message: "Durations must be positive") }
        return seconds
    }

    private func parseLevel(_ text: String) throws -> AwakeLevel {
        guard let flags = WireText.parseLevel(text) else { throw WireError(code: .badRequest, message: "Unknown level \(text)") }
        return AwakeLevel(display: flags.display, lid: flags.lid)
    }

    /// The reason cleaned for display, or nil when none was given or nothing is left of it.
    private func cleaned(_ reason: String?) -> String? {
        reason.map(CallerPolicy.cleanReason).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func requireUnreserved(_ id: String) throws {
        if CallerPolicy.isReserved(id) { throw WireError(code: .badRequest, message: "\(id) is reserved") }
    }
}

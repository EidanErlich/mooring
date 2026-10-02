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
    init(_ lease: Lease) {
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
            expiresAt: lease.expiresAt, watchPid: lease.watch?.pid, ttl: lease.ttl
        )
    }
}

/// Turns a decoded CLI request into engine calls, through `CallerPolicy`, and builds the reply.
@MainActor
final class RequestHandler {
    private let engine: AwakeEngine
    private let settings: @MainActor () -> AwakeSettings
    private let helperStatus: @MainActor () -> String
    private let readHelperSleepDisabled: @MainActor () async -> Bool?
    private let now: @MainActor () -> Date
    private let log = Logger(subsystem: "dev.mooring", category: "ipc")
    /// The id `mooring on` used before it became the menu's On switch.
    private static let legacyCLILeaseID = "cli"

    init(
        engine: AwakeEngine, settings: @escaping @MainActor () -> AwakeSettings,
        helperStatus: @escaping @MainActor () -> String, readHelperSleepDisabled: @escaping @MainActor () async -> Bool?,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.engine = engine
        self.settings = settings
        self.helperStatus = helperStatus
        self.readHelperSleepDisabled = readHelperSleepDisabled
        self.now = now
    }

    func handle(_ request: Request, from caller: Caller) async -> Response {
        do {
            switch request.args {
            case .acquire(let args) where args.kind == .on:
                return .success(id: request.id, .acquire(try turnOn(args)))
            case .acquire(let args): return .success(id: request.id, .acquire(try acquire(args, from: caller)))
            case .renew(let args): return .success(id: request.id, .renew(try renew(args)))
            case .release(let args): return .success(id: request.id, .release(try release(args)))
            case .status: return .success(id: request.id, .status(await status()))
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

    private func acquire(_ args: AcquireArgs, from caller: Caller) throws -> MooringIPC.AcquireResult {
        var plan = try plan(for: args, from: caller)
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
        // The engine reconciles inside `acquire`, so its suspensions already account for this lease.
        if let message = guardrailMessage(holdingBack: outcome.lease.level) {
            throw WireError(code: .guardrail, message: Self.holdNotice(message, kind: args.kind, id: plan.id))
        }
        let cutShort = plan.ttl.map { requested in granted.map { $0 < requested } ?? false } ?? false
        return MooringIPC.AcquireResult(lease: LeaseInfo(outcome.lease), clamped: outcome.wasClamped || cutShort)
    }

    /// `mooring on`: the menu's On switch. With no flags it leaves a running session alone; with
    /// `--for` or `--level` it replaces the session (and any picked apps), as picking a duration does.
    private func turnOn(_ args: AcquireArgs) throws -> MooringIPC.AcquireResult {
        let ttl = try positive(args.ttl)
        let level = try args.level.map(parseLevel)
        let current = now()
        let unchanged = ttl == nil && level == nil ? engine.menuLease ?? engine.sessionApps.first : nil
        if unchanged == nil {
            _ = try grantedDuration(
                for: Plan(
                    id: AwakeEngine.menuLeaseID, owner: .menu, reason: AwakeEngine.menuReason, level: level ?? .system,
                    ttl: ttl, watchPID: nil, caller: .trusted
                ),
                liveLeases: engine.leases.filter { $0.isLive(at: current) }.count, exists: engine.hasMenuSession
            )
            engine.turnOnMenu(duration: ttl ?? settings().clickDuration, level: level)
        }
        guard let lease = unchanged ?? engine.menuLease else {
            throw WireError(code: .internal, message: "Couldn't turn on")
        }
        if let message = guardrailMessage(holdingBack: lease.level) {
            throw WireError(code: .guardrail, message: Self.holdNotice(message, kind: .on, id: lease.id))
        }
        return MooringIPC.AcquireResult(lease: LeaseInfo(lease), clamped: false)
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
        // The helper read suspends, so take it first and read the engine in one synchronous stretch.
        let helperSleepDisabled = await readHelperSleepDisabled()
        let current = now()
        let state = engine.state
        let live = engine.leases.filter { $0.isLive(at: current) }
        return StatusResult(
            summary: StatusLine.text(leases: engine.leases, state: state, now: current),
            effective: LevelInfo(system: state.systemAssertion, display: state.displayAssertion, lid: state.lidSleepDisabled),
            systemAssertion: state.systemAssertion, displayAssertion: state.displayAssertion,
            lidSleepDisabled: state.lidSleepDisabled, helperSleepDisabled: helperSleepDisabled,
            wantsLid: engine.wantsLid, leases: live.map(LeaseInfo.init),
            power: PowerInfo(onAC: engine.power.onAC, batteryPercent: engine.power.batteryPercent),
            thermal: Self.thermalName(engine.thermal), lidClosed: engine.lidClosed, helper: helperStatus(),
            suspensions: state.suspensions.map { String(describing: $0) }.sorted()
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

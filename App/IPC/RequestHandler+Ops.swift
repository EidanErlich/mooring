import AwakeKit
import Foundation
import MooringIPC

extension RequestHandler {
    /// The id `mooring on` used before it became the menu's On switch.
    private static let legacyCLILeaseID = "cli"

    // MARK: - renew and release

    func renew(_ args: RenewArgs) throws -> LeaseInfo {
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

    func release(_ args: ReleaseArgs) throws -> ReleaseResult {
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

    func status() async -> StatusResult {
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
    func positive(_ seconds: Double?) throws -> Double? {
        guard let seconds else { return nil }
        guard seconds.isFinite, seconds > 0 else { throw WireError(code: .badRequest, message: "Durations must be positive") }
        return seconds
    }

    func parseLevel(_ text: String) throws -> AwakeLevel {
        guard let flags = WireText.parseLevel(text) else { throw WireError(code: .badRequest, message: "Unknown level \(text)") }
        return AwakeLevel(display: flags.display, lid: flags.lid)
    }

    /// The reason cleaned for display, or nil when none was given or nothing is left of it.
    func cleaned(_ reason: String?) -> String? {
        reason.map(CallerPolicy.cleanReason).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func requireUnreserved(_ id: String) throws {
        if CallerPolicy.isReserved(id) { throw WireError(code: .badRequest, message: "\(id) is reserved") }
    }
}

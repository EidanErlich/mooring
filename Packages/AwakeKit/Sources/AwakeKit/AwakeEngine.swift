@preconcurrency import AwaykeMonitors
import Foundation
import Observation
import os

public struct AcquireResult: Equatable, Sendable {
    public let lease: Lease
    /// The requested duration was longer than `AwakeEngine.maxLeaseLength`.
    public let wasClamped: Bool
}

/// The one engine every caller ends in (docs/SPEC.md 1.2). It holds the lease
/// table and, on every change and every tick, makes the IOKit assertions and
/// lid mode match the union of the live leases minus the guardrails, calling
/// IOKit and the helper only when something changed.
@MainActor
@Observable
public final class AwakeEngine {
    public static let maxLeaseLength: TimeInterval = 12 * 3600
    public static let menuLeaseID = "menu"
    public static let menuReason = "Turned on from the menu bar"
    public static let lidSessionID = "lid-session"
    public static let lidSessionReason = "Until I open the lid"

    /// Ordered by creation.
    public private(set) var leases: [Lease] = []
    /// What is actually applied, plus the active guardrail suspensions.
    public private(set) var state = TargetState.off
    public private(set) var power = PowerSnapshot(onAC: true, batteryPercent: nil)
    public private(set) var thermal = ProcessInfo.ThermalState.nominal
    public private(set) var lidClosed: Bool?

    /// Called with the suspensions a reconcile just added, for notifications.
    @ObservationIgnored public var onSuspensionsAdded: (@MainActor (Set<Suspension>) -> Void)?

    @ObservationIgnored private let assertions: any AssertionApplying
    @ObservationIgnored private let store: any LeaseStoring
    @ObservationIgnored private let processes: any ProcessInspecting
    @ObservationIgnored private let lid: any LidApplying
    @ObservationIgnored let settings: @MainActor () -> AwakeSettings
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var watches: [String: any ProcessWatch] = [:]
    @ObservationIgnored private var lidSessions: [String: LidSessionTracker] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "dev.mooring", category: "engine")
    @ObservationIgnored private let guardrailLog = Logger(subsystem: "dev.mooring", category: "guardrail")

    public init(
        assertions: any AssertionApplying, store: any LeaseStoring, processes: any ProcessInspecting,
        lid: any LidApplying, settings: @escaping @MainActor () -> AwakeSettings,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.assertions = assertions
        self.store = store
        self.processes = processes
        self.lid = lid
        self.settings = settings
        self.now = now
        lid.onChange = { [weak self] in self?.reconcile() }
    }

    public var menuLease: Lease? {
        leases.first { $0.id == Self.menuLeaseID }
    }

    /// Some live lease asks for lid mode, whether or not it can be applied.
    public var wantsLid: Bool {
        let current = now()
        return leases.contains { $0.level.lid && $0.isLive(at: current) }
    }

    // MARK: - Leases

    /// Creates the lease, or renews it if the id exists (keeping its creation time).
    /// Returns nil when `watchPID` names a process that isn't running.
    @discardableResult
    public func acquire(
        id: String, owner: LeaseOwner, reason: String, level: AwakeLevel,
        duration: TimeInterval?, watchPID: Int32? = nil, endsOnLidOpen: Bool = false
    ) -> AcquireResult? {
        let current = now()
        var watch: WatchedProcess?
        if let watchPID {
            guard let started = processes.startTime(of: watchPID) else {
                log.notice("not anchoring \(id, privacy: .public): process \(watchPID) isn't running")
                return nil
            }
            watch = WatchedProcess(pid: watchPID, startTime: started)
        }

        let clamped = duration.map { $0 > Self.maxLeaseLength } ?? false
        let granted = duration.map { min($0, Self.maxLeaseLength) }
        let expiresAt = granted.map { current.addingTimeInterval($0) }
        let existing = leases.firstIndex { $0.id == id }
        let lease = Lease(
            id: id, owner: owner, reason: reason, level: level, expiresAt: expiresAt, watch: watch,
            endsOnLidOpen: endsOnLidOpen, createdAt: existing.map { leases[$0].createdAt } ?? current,
            ttl: granted
        )

        if let existing {
            leases[existing] = lease
            log.notice("renewed \(id, privacy: .public): \(reason, privacy: .public)")
        } else {
            leases.append(lease)
            log.notice("created \(id, privacy: .public): \(reason, privacy: .public)")
        }
        rewatch(lease)
        retrackLid(lease)
        commit()
        return AcquireResult(lease: lease, wasClamped: clamped)
    }

    public func setLevel(_ level: AwakeLevel, forLease id: String) {
        guard let index = leases.firstIndex(where: { $0.id == id }) else { return }
        leases[index].level = level
        log.notice("changed level of \(id, privacy: .public): display \(level.display), lid \(level.lid)")
        commit()
    }

    /// Pushes the lease's expiry out to `ttl` from now (or its last TTL when `ttl` is nil),
    /// clamped to `maxLeaseLength`. Returns nil when there is no such lease; changes nothing
    /// when neither TTL is known.
    @discardableResult
    public func renew(id: String, ttl: TimeInterval?) -> Lease? {
        guard let index = leases.firstIndex(where: { $0.id == id }) else { return nil }
        guard let length = (ttl ?? leases[index].ttl).map({ min($0, Self.maxLeaseLength) }) else {
            return leases[index]
        }
        leases[index].expiresAt = now().addingTimeInterval(length)
        leases[index].ttl = length
        log.notice("renewed \(id, privacy: .public)")
        commit()
        return leases[index]
    }

    /// Moves the lease's expiry to `date` if that is earlier than its current one (or it has none).
    /// Returns false when there is no such lease.
    @discardableResult
    public func shorten(id: String, to date: Date) -> Bool {
        guard let index = leases.firstIndex(where: { $0.id == id }) else { return false }
        leases[index].expiresAt = min(leases[index].expiresAt ?? date, date)
        log.notice("shortened \(id, privacy: .public)")
        commit()
        return true
    }

    public func release(id: String) {
        guard let index = leases.firstIndex(where: { $0.id == id }) else { return }
        let lease = leases.remove(at: index)
        watches.removeValue(forKey: id)?.cancel()
        lidSessions[id] = nil
        log.notice("ended \(id, privacy: .public): \(lease.reason, privacy: .public)")
        commit()
    }

    /// Drops expired leases and reconciles. Runs every 5 s and on wake.
    public func tick() {
        let current = now()
        let expired = leases.filter { !$0.isLive(at: current) }
        guard !expired.isEmpty else {
            reconcile()
            return
        }
        for lease in expired {
            watches.removeValue(forKey: lease.id)?.cancel()
            lidSessions[lease.id] = nil
            log.notice("expired \(lease.id, privacy: .public): \(lease.reason, privacy: .public)")
        }
        leases.removeAll { !$0.isLive(at: current) }
        commit()
    }

    /// Restores the leases saved at the last change that are still in date and
    /// whose watched process is still the same process.
    /// Expiries are clamped to `maxLeaseLength` again, in case the file was edited.
    public func restore() {
        let current = now()
        let saved = store.load()
        // "Until I open the lid" isn't restored: the lid may have been opened while
        // Mooring wasn't running, and the session would wait for a close that already happened.
        let kept = LeaseRestore.restorable(saved, now: current, processes: processes).filter { !$0.endsOnLidOpen }
        for lease in saved where !kept.contains(where: { $0.id == lease.id }) {
            let cause = lease.endsOnLidOpen ? "lid sessions don't survive a relaunch"
                : lease.isLive(at: current) ? "its watched process is gone or its PID was reused" : "it expired"
            log.notice("not restoring \(lease.id, privacy: .public) (\(lease.reason, privacy: .public)): \(cause, privacy: .public)")
        }
        let latest = current.addingTimeInterval(Self.maxLeaseLength)
        leases = kept.map { lease in
            var lease = lease
            if let expiry = lease.expiresAt, expiry > latest { lease.expiresAt = latest }
            return lease
        }
        leases.forEach(rewatch)
        leases.forEach(retrackLid)
        log.notice("restored \(self.leases.count) lease(s)")
        commit()
    }

    // MARK: - Guardrail inputs

    public func update(power: PowerSnapshot) {
        guard power != self.power else { return }
        self.power = power
        reconcile()
    }

    public func update(thermal: ProcessInfo.ThermalState) {
        guard thermal != self.thermal else { return }
        self.thermal = thermal
        reconcile()
    }

    /// Also ends "Until I open the lid" sessions whose lid has been closed and reopened.
    public func update(lidClosed: Bool?) {
        guard lidClosed != self.lidClosed else { return }
        self.lidClosed = lidClosed
        if let lidClosed {
            let ended = lidSessions.filter { $0.value.handle(lidClosed: lidClosed) }.map(\.key)
            for id in ended {
                log.notice("lid reopened, ending \(id, privacy: .public)")
                release(id: id)
            }
        }
        reconcile()
    }

    public func systemDidWake() {
        tick()
        if settings().endMenuLeaseAfterSleep {
            endMenuSession()
        }
    }

    // MARK: - Private

    private func rewatch(_ lease: Lease) {
        watches.removeValue(forKey: lease.id)?.cancel()
        guard let watch = lease.watch else { return }
        watches[lease.id] = processes.watchExit(of: watch.pid) { [weak self] in
            self?.processExited(leaseID: lease.id)
        }
    }

    private func retrackLid(_ lease: Lease) {
        guard lease.endsOnLidOpen else {
            lidSessions[lease.id] = nil
            return
        }
        let tracker = LidSessionTracker()
        tracker.start(lidClosed: lidClosed)
        lidSessions[lease.id] = tracker
    }

    private func processExited(leaseID: String) {
        watches[leaseID] = nil
        guard let index = leases.firstIndex(where: { $0.id == leaseID }) else { return }
        let lease = leases.remove(at: index)
        log.notice("ended \(leaseID, privacy: .public): watched process exited (\(lease.reason, privacy: .public))")
        commit()
    }

    private func commit() {
        store.save(leases)
        reconcile()
    }

    /// `state` records what is actually held (assertions IOKit granted, lid mode
    /// the helper confirmed), so nothing reads as On that isn't, and the next
    /// tick retries anything that failed.
    private func reconcile() {
        var next = target(
            leases: leases, power: power, thermal: thermal, lidClosed: lidClosed,
            settings: settings(), now: now(), suspended: state.suspensions
        )
        if next.systemAssertion != state.systemAssertion || next.displayAssertion != state.displayAssertion {
            let held = assertions.apply(system: next.systemAssertion, display: next.displayAssertion)
            next.systemAssertion = held.system
            next.displayAssertion = held.display
        }

        let wantedLid = next.lidSleepDisabled && lid.isAvailable
        if lid.applied != wantedLid && !lid.isBusy && lid.isAvailable {
            lid.apply(wantedLid)
        }
        next.lidSleepDisabled = lid.applied ?? false

        let added = next.suspensions.subtracting(state.suspensions)
        let removed = state.suspensions.subtracting(next.suspensions)
        for suspension in added {
            guardrailLog.notice("suspended: \(String(describing: suspension), privacy: .public)")
        }
        for suspension in removed {
            guardrailLog.notice("resumed: \(String(describing: suspension), privacy: .public)")
        }
        if next != state {
            state = next
        }
        if !added.isEmpty {
            onSuspensionsAdded?(added)
        }
    }
}

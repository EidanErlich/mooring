import Foundation
import Observation
import os

public struct AcquireResult: Equatable, Sendable {
    public let lease: Lease
    /// The requested duration was longer than `AwakeEngine.maxLeaseLength`.
    public let wasClamped: Bool
}

/// The one engine every caller ends in (docs/SPEC.md 1.2). It holds the lease
/// table and, on every change and every tick, makes the IOKit assertions match
/// the union of the live leases, calling IOKit only when something changed.
@MainActor
@Observable
public final class AwakeEngine {
    public static let maxLeaseLength: TimeInterval = 12 * 3600
    public static let menuLeaseID = "menu"
    public static let menuReason = "Turned on from the menu bar"

    /// Ordered by creation.
    public private(set) var leases: [Lease] = []
    /// What was last applied.
    public private(set) var state = TargetState.off

    @ObservationIgnored private let assertions: any AssertionApplying
    @ObservationIgnored private let store: any LeaseStoring
    @ObservationIgnored private let processes: any ProcessInspecting
    @ObservationIgnored private let settings: @MainActor () -> AwakeSettings
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var watches: [String: any ProcessWatch] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "dev.mooring", category: "engine")

    public init(
        assertions: any AssertionApplying, store: any LeaseStoring, processes: any ProcessInspecting,
        settings: @escaping @MainActor () -> AwakeSettings, now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.assertions = assertions
        self.store = store
        self.processes = processes
        self.settings = settings
        self.now = now
    }

    public var menuLease: Lease? {
        leases.first { $0.id == Self.menuLeaseID }
    }

    // MARK: - Leases

    /// Creates the lease, or renews it if the id exists (keeping its creation time).
    /// Returns nil when `watchPID` names a process that isn't running.
    @discardableResult
    public func acquire(
        id: String, owner: LeaseOwner, reason: String, level: AwakeLevel,
        duration: TimeInterval?, watchPID: Int32? = nil
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
        let expiresAt = duration.map { current.addingTimeInterval(min($0, Self.maxLeaseLength)) }
        let existing = leases.firstIndex { $0.id == id }
        let lease = Lease(
            id: id, owner: owner, reason: reason, level: level, expiresAt: expiresAt, watch: watch,
            createdAt: existing.map { leases[$0].createdAt } ?? current
        )

        if let existing {
            leases[existing] = lease
            log.notice("renewed \(id, privacy: .public): \(reason, privacy: .public)")
        } else {
            leases.append(lease)
            log.notice("created \(id, privacy: .public): \(reason, privacy: .public)")
        }
        rewatch(lease)
        commit()
        return AcquireResult(lease: lease, wasClamped: clamped)
    }

    public func setLevel(_ level: AwakeLevel, forLease id: String) {
        guard let index = leases.firstIndex(where: { $0.id == id }) else { return }
        leases[index].level = level
        commit()
    }

    public func release(id: String) {
        guard let index = leases.firstIndex(where: { $0.id == id }) else { return }
        let lease = leases.remove(at: index)
        watches.removeValue(forKey: id)?.cancel()
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
            log.notice("expired \(lease.id, privacy: .public): \(lease.reason, privacy: .public)")
        }
        leases.removeAll { !$0.isLive(at: current) }
        commit()
    }

    /// Restores the leases saved at the last change that are still in date and
    /// whose watched process is still the same process.
    public func restore() {
        leases = LeaseRestore.restorable(store.load(), now: now(), processes: processes)
        leases.forEach(rewatch)
        log.notice("restored \(self.leases.count) lease(s)")
        commit()
    }

    public func systemDidWake() {
        tick()
        if settings().endMenuLeaseAfterSleep {
            release(id: Self.menuLeaseID)
        }
    }

    // MARK: - Menu intents

    /// The icon's primary action: the menu lease at the user's On defaults, or off.
    public func toggleMenu() {
        if menuLease != nil {
            release(id: Self.menuLeaseID)
        } else {
            let defaults = settings()
            acquireMenu(level: defaults.clickLevel, duration: defaults.clickDuration)
        }
    }

    public func turnOnMenu(duration: TimeInterval?) {
        acquireMenu(level: menuLease?.level ?? settings().clickLevel, duration: duration)
    }

    public func setKeepScreenOn(_ enabled: Bool) {
        if var level = menuLease?.level {
            level.display = enabled
            setLevel(level, forLease: Self.menuLeaseID)
        } else if enabled {
            let defaults = settings()
            acquireMenu(level: defaults.clickLevel.union(.screenOn), duration: defaults.clickDuration)
        }
    }

    @discardableResult
    public func anchor(whileAppRuns pid: Int32, appName: String) -> Lease? {
        acquire(
            id: "app-\(pid)", owner: .menu, reason: "While \(appName) runs",
            level: settings().clickLevel, duration: nil, watchPID: pid
        )?.lease
    }

    // MARK: - Private

    private func acquireMenu(level: AwakeLevel, duration: TimeInterval?) {
        acquire(id: Self.menuLeaseID, owner: .menu, reason: Self.menuReason, level: level, duration: duration)
    }

    private func rewatch(_ lease: Lease) {
        watches.removeValue(forKey: lease.id)?.cancel()
        guard let watch = lease.watch else { return }
        watches[lease.id] = processes.watchExit(of: watch.pid) { [weak self] in
            self?.processExited(leaseID: lease.id)
        }
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

    /// `state` records what is actually held, so a refused assertion never reads
    /// as On, and the next tick tries again.
    private func reconcile() {
        var next = target(
            leases: leases, power: PowerSnapshot(onAC: true, batteryPercent: nil), thermal: .nominal,
            lidClosed: nil, settings: settings(), now: now()
        )
        if next.systemAssertion != state.systemAssertion || next.displayAssertion != state.displayAssertion {
            let held = assertions.apply(system: next.systemAssertion, display: next.displayAssertion)
            next.systemAssertion = held.system
            next.displayAssertion = held.display
        }
        if next != state {
            state = next
        }
    }
}

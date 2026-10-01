import AwakeKit
import Foundation
import os

/// The helper calls `LidController` needs; `HelperClient` is the real one.
@MainActor
protocol LidHelper: AnyObject {
    var status: HelperStatus { get }
    /// Called when the connection to the helper drops.
    var onConnectionLost: (@MainActor () -> Void)? { get set }
    func setLidSleepDisabled(_ disabled: Bool) async throws
    func lidSleepDisabled() async throws -> Bool
    func heartbeat() async throws -> Bool
    func unregister() async throws
}

extension HelperClient: LidHelper {}

/// Applies lid mode for the engine (docs/SPEC.md 1.5–1.6): one helper request
/// at a time, `applied` only ever holds what the helper confirmed, and while
/// lid mode is on it sends the helper's watchdog a heartbeat every 30 s.
@MainActor
final class LidController: LidApplying {
    static let heartbeatInterval: TimeInterval = 30

    private(set) var applied: Bool?
    private(set) var isBusy = false
    var onChange: (@MainActor () -> Void)?

    private let helper: any LidHelper
    private var task: Task<Void, Never>?
    private var recheck: Task<Void, Never>?
    private var heartbeatTimer: Timer?
    private var isShuttingDown = false
    private let log = Logger(subsystem: "dev.mooring", category: "helper")

    init(helper: any LidHelper) {
        self.helper = helper
        helper.onConnectionLost = { [weak self] in self?.connectionLost() }
        refresh()
    }

    /// The helper restarted or crashed. A stopping helper turns lid sleep back on,
    /// so check now rather than at the next 30 s heartbeat; the engine re-applies.
    private func connectionLost() {
        if applied == true {
            recheck = Task { await self.heartbeatNow() }
        } else {
            refresh()
        }
    }

    var isAvailable: Bool { helper.status == .enabled }

    func refresh() {
        run { [helper] in
            if let value = try? await helper.lidSleepDisabled() { self.applied = value }
        }
    }

    func apply(_ disabled: Bool) {
        guard !(isShuttingDown && disabled) else { return }
        run { [helper, log] in
            do {
                try await helper.setLidSleepDisabled(disabled)
                self.applied = disabled
            } catch {
                log.error("setting lid sleep to \(disabled) failed: \(error.localizedDescription, privacy: .public)")
                if let actual = try? await helper.lidSleepDisabled() { self.applied = actual }
            }
        }
    }

    /// What the heartbeat timer runs. A helper that restarted and lost lid mode
    /// replies with the real value, and the engine re-applies.
    func heartbeatNow() async {
        guard applied == true, isAvailable, let actual = try? await helper.heartbeat() else { return }
        if actual != applied {
            log.notice("heartbeat: helper reports SleepDisabled \(actual), expected \(self.applied == true)")
            applied = actual
            updateHeartbeat()
            onChange?()
        }
    }

    /// For quitting: restores lid sleep and refuses to disable it again, so the
    /// engine's next reconcile can't undo it while leases are kept for relaunch.
    func shutDown() async {
        isShuttingDown = true
        await settle()
        if applied != false {
            apply(false)
            await settle()
        }
    }

    /// "Uninstall helper…" (docs/SPEC.md 1.6, layer 4): restores lid sleep, then
    /// unregisters even if the restore failed, since with the helper down that is how
    /// the user recovers. The helper also restores on the SIGTERM unregistering sends.
    func uninstall() async throws {
        await shutDown()
        try await helper.unregister()
        applied = nil
        isShuttingDown = false
        updateHeartbeat()
        onChange?()
    }

    /// Waits for the request in flight, if any. For tests.
    func settle() async {
        await recheck?.value
        await task?.value
    }

    private func run(_ request: @escaping @MainActor () async -> Void) {
        guard isAvailable, !isBusy else { return }
        isBusy = true
        let before = applied
        task = Task { @MainActor in
            await request()
            self.isBusy = false
            // A newly armed heartbeat runs at once: a helper that restarted learns
            // it owns a SleepDisabled = 1 it didn't set (its watchdog then covers it).
            if self.updateHeartbeat() { await self.heartbeatNow() }
            // Only a change reaches the engine; failures retry on its 5 s tick
            // instead of looping on a helper that fails instantly.
            if self.applied != before { self.onChange?() }
        }
    }

    /// Returns true when it just armed the timer.
    @discardableResult
    private func updateHeartbeat() -> Bool {
        guard applied == true else {
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
            return false
        }
        guard heartbeatTimer == nil else { return false }
        let timer = Timer(timeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.heartbeatNow() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
        return true
    }
}

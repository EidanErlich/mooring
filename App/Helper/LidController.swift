import AwakeKit
import Foundation
import os

/// The helper calls `LidController` needs; `HelperClient` is the real one.
@MainActor
protocol LidHelper: AnyObject {
    var status: HelperStatus { get }
    func setLidSleepDisabled(_ disabled: Bool) async throws
    func lidSleepDisabled() async throws -> Bool
    func heartbeat() async throws -> Bool
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
    private var heartbeatTimer: Timer?
    private var isShuttingDown = false
    private let log = Logger(subsystem: "dev.mooring", category: "helper")

    init(helper: any LidHelper) {
        self.helper = helper
        refresh()
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

    /// Waits for the request in flight, if any. For tests.
    func settle() async {
        await task?.value
    }

    private func run(_ request: @escaping @MainActor () async -> Void) {
        guard isAvailable, !isBusy else { return }
        isBusy = true
        task = Task { @MainActor in
            await request()
            self.isBusy = false
            self.updateHeartbeat()
            self.onChange?()
        }
    }

    private func updateHeartbeat() {
        guard applied == true else {
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
            return
        }
        guard heartbeatTimer == nil else { return }
        let timer = Timer(timeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.heartbeatNow() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }
}

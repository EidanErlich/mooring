import Foundation

/// Restores sleep the helper disabled once the app is gone (docs/SPEC.md 1.6):
/// 10 s after its last connection closes, or 90 s after its last heartbeat.
struct Watchdog {
    static let reconnectGrace: TimeInterval = 10
    static let heartbeatTimeout: TimeInterval = 90

    private(set) var sleepDisabledByUs = false
    private var connections = 0
    private var orphanedSince: Date?
    private var lastHeartbeat: Date?

    mutating func didSetSleepDisabled(_ disabled: Bool, at now: Date) {
        sleepDisabledByUs = disabled
        lastHeartbeat = disabled ? now : nil
    }

    /// The app only heartbeats while it has lid mode on, so a heartbeat that finds
    /// SleepDisabled = 1 hands ownership back to a helper that restarted.
    mutating func didHeartbeat(at now: Date, sleepDisabled: Bool) {
        if sleepDisabled { sleepDisabledByUs = true }
        lastHeartbeat = now
    }

    /// At launch: a helper that owned SleepDisabled before it stopped (reboot, crash)
    /// treats the app as gone until it reconnects.
    mutating func didStart(owningSleep: Bool, at now: Date) {
        sleepDisabledByUs = owningSleep
        if owningSleep { orphanedSince = now }
    }

    mutating func connectionOpened() {
        connections += 1
        orphanedSince = nil
    }

    mutating func connectionClosed(at now: Date) {
        connections = max(0, connections - 1)
        if connections == 0 { orphanedSince = now }
    }

    func shouldRestore(at now: Date) -> Bool {
        let orphaned = connections == 0 && orphanedSince.map { now.timeIntervalSince($0) >= Self.reconnectGrace } == true
        let silent = lastHeartbeat.map { now.timeIntervalSince($0) >= Self.heartbeatTimeout } == true
        return sleepDisabledByUs && (orphaned || silent)
    }

    mutating func didRestore() { didSetSleepDisabled(false, at: Date()) }
}

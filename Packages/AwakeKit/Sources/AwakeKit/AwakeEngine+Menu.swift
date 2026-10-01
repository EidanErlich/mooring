import Foundation

/// What the menu-bar icon, the dropdown rows and Settings ask the engine to do.
///
/// The dropdown keeps one *menu session*: either a duration (the `menu` lease, timed
/// or until turned off) or one or more picked apps (`app-<pid>` leases), never both.
/// "Keep screen on" and "Allow lid close" apply to whichever it is, and carry over
/// when the user switches between a duration and apps.
extension AwakeEngine {
    static let appLeasePrefix = "app-"

    /// The apps picked under "While an app runs…", in the order they were picked.
    public var sessionApps: [Lease] {
        leases.filter { $0.owner == .menu && $0.id.hasPrefix(Self.appLeasePrefix) }
    }

    public var hasMenuSession: Bool {
        menuLease != nil || !sessionApps.isEmpty
    }

    /// The level the menu session runs at, or nil when there is no session.
    public var sessionLevel: AwakeLevel? {
        menuLease?.level ?? sessionApps.first?.level
    }

    /// The icon's primary action: ends the menu session, or starts one at the On defaults.
    public func toggleMenu() {
        if hasMenuSession {
            endMenuSession()
        } else {
            let defaults = settings()
            acquireMenu(level: defaults.clickLevel, duration: defaults.clickDuration)
        }
    }

    /// A duration (nil = until turned off) replaces any picked apps.
    public func turnOnMenu(duration: TimeInterval?) {
        turnOnMenu(duration: duration, level: nil)
    }

    /// As above, at `level` when given, else at the session's level, else at the On default.
    public func turnOnMenu(duration: TimeInterval?, level: AwakeLevel?) {
        let level = level ?? sessionLevel ?? settings().clickLevel
        sessionApps.forEach { release(id: $0.id) }
        acquireMenu(level: level, duration: duration)
    }

    public func setKeepScreenOn(_ enabled: Bool) {
        updateSessionLevel(orStartWith: enabled ? .screenOn : nil) { $0.display = enabled }
    }

    public func setAllowLidClose(_ enabled: Bool) {
        updateSessionLevel(orStartWith: enabled ? AwakeLevel(display: false, lid: true) : nil) { $0.lid = enabled }
    }

    /// "Until I open the lid": lid mode that ends after the lid is closed and reopened.
    public func startLidSession() {
        acquire(id: Self.lidSessionID, owner: .menu, reason: Self.lidSessionReason,
                level: AwakeLevel(display: false, lid: true), duration: nil, endsOnLidOpen: true)
    }

    /// Adds an app to the session; a running duration is replaced.
    @discardableResult
    public func anchor(whileAppRuns pid: Int32, appName: String) -> Lease? {
        let level = sessionLevel ?? settings().clickLevel
        guard let lease = acquire(
            id: "\(Self.appLeasePrefix)\(pid)", owner: .menu, reason: "While \(appName) runs",
            level: level, duration: nil, watchPID: pid
        )?.lease else { return nil }
        release(id: Self.menuLeaseID)
        return lease
    }

    func acquireMenu(level: AwakeLevel, duration: TimeInterval?) {
        acquire(id: Self.menuLeaseID, owner: .menu, reason: Self.menuReason, level: level, duration: duration)
    }

    /// Ends the menu session: the `menu` lease and every picked app.
    public func endMenuSession() {
        release(id: Self.menuLeaseID)
        sessionApps.forEach { release(id: $0.id) }
    }

    /// Changes the level of every lease in the session, or starts a session at the
    /// On defaults plus `start` when there is none.
    private func updateSessionLevel(orStartWith start: AwakeLevel?, _ change: (inout AwakeLevel) -> Void) {
        let session = (menuLease.map { [$0] } ?? []) + sessionApps
        guard !session.isEmpty else {
            guard let start else { return }
            let defaults = settings()
            acquireMenu(level: defaults.clickLevel.union(start), duration: defaults.clickDuration)
            return
        }
        for lease in session {
            var level = lease.level
            change(&level)
            setLevel(level, forLease: lease.id)
        }
    }
}

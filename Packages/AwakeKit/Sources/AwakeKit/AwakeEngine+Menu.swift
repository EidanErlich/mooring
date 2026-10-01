import Foundation

/// What the menu-bar icon, the dropdown rows and Settings ask the engine to do.
extension AwakeEngine {
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

    public func setAllowLidClose(_ enabled: Bool) {
        if var level = menuLease?.level {
            level.lid = enabled
            setLevel(level, forLease: Self.menuLeaseID)
        } else if enabled {
            let defaults = settings()
            acquireMenu(level: defaults.clickLevel.union(AwakeLevel(display: false, lid: true)),
                        duration: defaults.clickDuration)
        }
    }

    /// "Until I open the lid": lid mode that ends after the lid is closed and reopened.
    public func startLidSession() {
        acquire(id: Self.lidSessionID, owner: .menu, reason: Self.lidSessionReason,
                level: AwakeLevel(display: false, lid: true), duration: nil, endsOnLidOpen: true)
    }

    @discardableResult
    public func anchor(whileAppRuns pid: Int32, appName: String) -> Lease? {
        acquire(
            id: "app-\(pid)", owner: .menu, reason: "While \(appName) runs",
            level: settings().clickLevel, duration: nil, watchPID: pid
        )?.lease
    }

    func acquireMenu(level: AwakeLevel, duration: TimeInterval?) {
        acquire(id: Self.menuLeaseID, owner: .menu, reason: Self.menuReason, level: level, duration: duration)
    }
}

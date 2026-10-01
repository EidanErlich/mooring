import Foundation

/// Countdown text. Minutes round up, so a live lease never reads "0m".
public enum DurationText {
    // Same formatting as `CLIText.remaining` in Packages/MooringIPC/Sources/MooringCLICore/Output.swift; keep them identical.
    /// Negative time (a lease expired but not yet ticked away) reads as "0m".
    public static func remaining(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.up))
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(rest)m"
        }
    }
}

/// The dropdown's first line: "Off", or "On · …" describing the lease that ends last.
public enum StatusLine {
    public static func text(leases: [Lease], state: TargetState, now: Date) -> String {
        guard let last = LeaseText.endingLast(leases, now: now) else { return "Off" }
        var parts = ["On"]
        if state.displayAssertion { parts.append("screen on") }
        if state.lidSleepDisabled {
            parts.append("lid mode")
        } else if !state.suspensions.isDisjoint(with: [.lidNeedsAC, .lowBatteryLid, .thermal]) {
            parts.append("lid mode paused")
        }
        switch (last.expiresAt, last.watch) {
        case (let expiry?, _):
            parts.append("\(DurationText.remaining(expiry.timeIntervalSince(now))) left")
        case (nil, nil):
            parts.append("until turned off")
        case (nil, _?):
            let tasks = leases.filter { $0.isLive(at: now) && $0.expiresAt == nil && $0.watch != nil }.count
            parts.append(tasks > 1 ? "while \(tasks) apps run" : last.reason.prefix(1).lowercased() + last.reason.dropFirst())
        }
        return parts.joined(separator: " · ")
    }
}

/// Text for one row of the Anchored list.
public enum LeaseText {
    /// The live lease that keeps the Mac awake longest, which the status line and
    /// the menu-bar icon both describe. Until turned off outlasts a watched process,
    /// which outlasts any expiry; ties go to the earliest lease.
    public static func endingLast(_ leases: [Lease], now: Date) -> Lease? {
        func rank(_ lease: Lease) -> (Int, Date) {
            switch (lease.expiresAt, lease.watch) {
            case (nil, nil): (2, .distantFuture)
            case (nil, _?): (1, .distantFuture)
            case (let expiry?, _): (0, expiry)
            }
        }
        return leases.filter { $0.isLive(at: now) }.reduce(nil) { best, lease in
            guard let best else { return lease }
            return rank(lease) > rank(best) ? lease : best
        }
    }

    public static func owner(_ owner: LeaseOwner) -> String {
        switch owner {
        case .menu: "Menu bar"
        case .cli: "Terminal"
        case .agent(let name): name
        case .mcp(let client): client
        }
    }

    public static func timeLeft(_ lease: Lease, now: Date) -> String {
        switch (lease.expiresAt, lease.watch) {
        case (let expiry?, _): "\(DurationText.remaining(expiry.timeIntervalSince(now))) left"
        case (nil, nil): "Until turned off"
        case (nil, _?): "While running"
        }
    }
}

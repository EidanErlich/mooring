import AwakeKit
import Foundation

/// What kind of awake the pill's label describes (docs/superpowers/specs/2026-10-01-menu-bar-icon-design.md).
enum AwakeKind: Equatable {
    case indefinite
    case task
    /// Seconds left; nil when "Show time left in the menu bar" is off.
    case timed(TimeInterval?)
}

enum Attention: Equatable {
    case suspension(Suspension)
    case helperNeedsApproval
}

/// Everything the menu-bar icon shows. Precedence: attention, then awake, then off.
enum MenuBarState: Equatable {
    case off
    case awake(lid: Bool, kind: AwakeKind)
    case attention(Attention)

    private static let attentionPriority: [Suspension] = [.lowBatteryAll, .lowBatteryLid, .thermal, .lidNeedsAC]

    // The spec fixes these six inputs; bundling them only to satisfy the linter would hide them.
    // swiftlint:disable:next function_parameter_count
    static func from(
        leases: [Lease], state: TargetState, wantsLid: Bool, helperEnabled: Bool, showTimeLeft: Bool, now: Date
    ) -> MenuBarState {
        if let suspension = attentionPriority.first(where: state.suspensions.contains) {
            return .attention(.suspension(suspension))
        }
        if wantsLid && !helperEnabled {
            return .attention(.helperNeedsApproval)
        }
        guard state.systemAssertion else { return .off }
        return .awake(lid: state.lidSleepDisabled, kind: kind(of: LeaseText.endingLast(leases, now: now),
                                                              showTimeLeft: showTimeLeft, now: now))
    }

    private static func kind(of lease: Lease?, showTimeLeft: Bool, now: Date) -> AwakeKind {
        switch (lease?.expiresAt, lease?.watch) {
        case (let expiry?, _): .timed(showTimeLeft ? expiry.timeIntervalSince(now) : nil)
        case (nil, _?): .task
        case (nil, nil): .indefinite
        }
    }
}

enum MenuBarText {
    /// `1:12` from an hour up, `42m` below; minutes round up, so a live lease never reads `0m`.
    static func timeLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return minutes >= 60 ? String(format: "%d:%02d", minutes / 60, minutes % 60) : "\(minutes)m"
    }

    static func accessibilityLabel(for state: MenuBarState) -> String {
        switch state {
        case .off:
            return "Mooring, off"
        case .awake(let lid, let kind):
            let mode = lid ? "Mooring, lid mode" : "Mooring, on"
            switch kind {
            case .indefinite: return "\(mode), until turned off"
            case .task: return "\(mode), while an app runs"
            case .timed(nil): return mode
            case .timed(let seconds?): return "\(mode), \(spoken(seconds)) left"
            }
        case .attention(.suspension(.lowBatteryAll)):
            return "Mooring paused, battery low"
        case .attention(.suspension(let suspension)):
            return "Mooring needs attention: lid mode paused, \(reason(suspension))"
        case .attention(.helperNeedsApproval):
            return "Mooring needs attention: helper needs approval"
        }
    }

    private static func reason(_ suspension: Suspension) -> String {
        switch suspension {
        case .lowBatteryLid, .lowBatteryAll: "battery low"
        case .thermal: "Mac too warm"
        case .lidNeedsAC: "needs power"
        }
    }

    private static func spoken(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        func unit(_ count: Int, _ name: String) -> String { "\(count) \(name)\(count == 1 ? "" : "s")" }
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return unit(rest, "minute")
        case (_, 0): return unit(hours, "hour")
        default: return "\(unit(hours, "hour")) \(unit(rest, "minute"))"
        }
    }
}

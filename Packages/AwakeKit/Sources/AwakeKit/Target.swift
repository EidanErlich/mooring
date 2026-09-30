import Foundation

public enum Suspension: Equatable, Hashable, Sendable {
    case lidNeedsAC, lowBatteryLid, lowBatteryAll, thermal
}

/// What the reconciler makes reality match.
public struct TargetState: Equatable, Sendable {
    public var systemAssertion: Bool
    public var displayAssertion: Bool
    public var lidSleepDisabled: Bool
    public var suspensions: Set<Suspension>

    public init(systemAssertion: Bool, displayAssertion: Bool, lidSleepDisabled: Bool, suspensions: Set<Suspension>) {
        self.systemAssertion = systemAssertion
        self.displayAssertion = displayAssertion
        self.lidSleepDisabled = lidSleepDisabled
        self.suspensions = suspensions
    }

    public static let off = TargetState(systemAssertion: false, displayAssertion: false, lidSleepDisabled: false, suspensions: [])
}

public struct PowerSnapshot: Equatable, Sendable {
    public var onAC: Bool
    /// nil on Macs without a battery.
    public var batteryPercent: Int?

    public init(onAC: Bool, batteryPercent: Int?) {
        self.onAC = onAC
        self.batteryPercent = batteryPercent
    }
}

// The signature is fixed by docs/SPEC.md (Core types); the guardrails in 1c use every input.
// swiftlint:disable function_parameter_count
/// The effective state for a set of leases: the per-flag union over live leases.
/// `power`, `thermal`, `lidClosed` and `settings` feed the guardrails, which
/// arrive in stage 1c; until then no suspensions are produced.
public func target(
    leases: [Lease], power: PowerSnapshot, thermal: ProcessInfo.ThermalState,
    lidClosed: Bool?, settings: AwakeSettings, now: Date
) -> TargetState {
    let live = leases.filter { $0.isLive(at: now) }
    let level = live.reduce(AwakeLevel.system) { $0.union($1.level) }
    return TargetState(
        systemAssertion: !live.isEmpty,
        displayAssertion: level.display,
        lidSleepDisabled: level.lid,
        suspensions: []
    )
}
// swiftlint:enable function_parameter_count

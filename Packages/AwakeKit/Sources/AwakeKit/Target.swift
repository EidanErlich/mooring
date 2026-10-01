import AwaykeMonitors
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

// The signature follows docs/SPEC.md (Core types) plus `suspended`, the previous
// suspensions, which the guardrails need for hysteresis.
// swiftlint:disable function_parameter_count
/// The effective state for a set of leases: the per-flag union over live leases,
/// minus whatever the guardrails (docs/SPEC.md 1.7) suspend. Guardrails never
/// change leases; they only decide what is applied.
public func target(
    leases: [Lease], power: PowerSnapshot, thermal: ProcessInfo.ThermalState,
    lidClosed: Bool?, settings: AwakeSettings, now: Date, suspended: Set<Suspension> = []
) -> TargetState {
    let live = leases.filter { $0.isLive(at: now) }
    let level = live.reduce(AwakeLevel.system) { $0.union($1.level) }
    let onBattery = !power.onAC && power.batteryPercent != nil
    var suspensions = Set<Suspension>()

    // Low battery, all awake: below the threshold on battery; resumes on AC.
    if !live.isEmpty, let threshold = settings.allBatteryThreshold, let percent = power.batteryPercent {
        let wasSuspended = suspended.contains(.lowBatteryAll)
        if wasSuspended ? !power.onAC : (onBattery && percent < threshold) {
            suspensions.insert(.lowBatteryAll)
        }
    }

    if level.lid {
        suspensions.formUnion(lidSuspensions(power: power, thermal: thermal, lidClosed: lidClosed,
                                             settings: settings, suspended: suspended))
    }

    let allPaused = suspensions.contains(.lowBatteryAll)
    let lidPaused = !suspensions.isDisjoint(with: [.lidNeedsAC, .lowBatteryLid, .thermal])
    return TargetState(
        systemAssertion: !live.isEmpty && !allPaused,
        displayAssertion: level.display && !allPaused,
        lidSleepDisabled: level.lid && !lidPaused && !allPaused,
        suspensions: suspensions
    )
}

/// The guardrails that pause only lid mode, while some live lease wants it.
private func lidSuspensions(
    power: PowerSnapshot, thermal: ProcessInfo.ThermalState, lidClosed: Bool?,
    settings: AwakeSettings, suspended: Set<Suspension>
) -> Set<Suspension> {
    var suspensions = Set<Suspension>()
    // Low battery, lid mode: Awayke's policy, resuming on AC at threshold + 5.
    if let threshold = settings.lidBatteryThreshold {
        let wasSuspended = suspended.contains(.lowBatteryLid)
        switch AutoOffPolicy.decide(intent: true, suspended: wasSuspended, percent: power.batteryPercent ?? 100,
                                    onAC: power.onAC, threshold: threshold) {
        case .suspend: suspensions.insert(.lowBatteryLid)
        case .resume: break
        case .none: if wasSuspended { suspensions.insert(.lowBatteryLid) }
        }
    }
    // Thermal: serious or worse with the lid closed; resumes at nominal.
    if settings.thermalCutoff {
        let hot = lidClosed == true && thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        if suspended.contains(.thermal) ? thermal != .nominal : hot {
            suspensions.insert(.thermal)
        }
    }
    // Lid mode on battery needs the user's opt-in.
    if !power.onAC && power.batteryPercent != nil && !settings.allowLidOnBattery {
        suspensions.insert(.lidNeedsAC)
    }
    return suspensions
}
// swiftlint:enable function_parameter_count

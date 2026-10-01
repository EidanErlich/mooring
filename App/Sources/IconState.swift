import AwakeKit

/// The small symbol drawn at the icon's bottom right (docs/SPEC.md, Icon states).
enum IconBadge: Equatable {
    case none, lid, lidOnBattery
}

/// Everything the menu-bar icon shows, derived from the engine.
struct IconState: Equatable {
    var filled: Bool
    var badge: IconBadge
    var attention: Bool

    static func from(state: TargetState, wantsLid: Bool, helperEnabled: Bool, power: PowerSnapshot) -> IconState {
        let badge: IconBadge = !state.lidSleepDisabled ? .none : (power.onAC ? .lid : .lidOnBattery)
        let attention = (wantsLid && !helperEnabled) || !state.suspensions.isEmpty
        return IconState(filled: state.systemAssertion, badge: badge, attention: attention)
    }
}

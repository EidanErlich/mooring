import Foundation

public enum AgentMode: String, Codable, Sendable {
    case automatic, explicit
}

public enum AgentLidMode: String, Codable, Sendable {
    case askEachTime, alwaysAllow, never
}

public enum AgentWindowMode: String, Codable, Sendable {
    case automatic, askFirst, off
}

/// Everything the engine and its callers read from Settings (docs/SPEC.md,
/// Engineering decisions → Core types).
public struct AwakeSettings: Codable, Equatable, Sendable {
    /// What a left click turns On with.
    public var clickLevel = AwakeLevel.system
    /// nil = until turned off.
    public var clickDuration: TimeInterval?
    public var endMenuLeaseAfterSleep = false
    /// Set by the lid-on-battery opt-in sheet.
    public var allowLidOnBattery = false
    /// nil = off.
    public var lidBatteryThreshold: Int? = 20
    /// nil = off.
    public var allBatteryThreshold: Int? = 10
    public var thermalCutoff = true
    public var agentKeepAwake = AgentMode.automatic
    public var agentLid = AgentLidMode.askEachTime
    public var agentWindows = AgentWindowMode.automatic

    public init() {}
}

/// The durations the menu and Settings offer (Chai's set, plus "Until turned off").
public enum AwakeDuration: CaseIterable, Sendable {
    case minutes30, hour1, hours2, hours4, hours8, untilTurnedOff

    public var interval: TimeInterval? {
        switch self {
        case .minutes30: 1800
        case .hour1: 3600
        case .hours2: 7200
        case .hours4: 14400
        case .hours8: 28800
        case .untilTurnedOff: nil
        }
    }

    public var title: String {
        switch self {
        case .minutes30: "30 min"
        case .hour1: "1 h"
        case .hours2: "2 h"
        case .hours4: "4 h"
        case .hours8: "8 h"
        case .untilTurnedOff: "Until turned off"
        }
    }

    /// The option with exactly this interval; anything else reads as "Until turned off".
    public init(interval: TimeInterval?) {
        self = Self.allCases.first { $0.interval == interval } ?? .untilTurnedOff
    }
}

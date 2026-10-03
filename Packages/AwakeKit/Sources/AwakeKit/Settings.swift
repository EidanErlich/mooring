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
    /// Superseded by `agentLidApproval`; no screen sets it and nothing reads it.
    public var agentLid = AgentLidMode.askEachTime
    /// "Lid mode for agents".
    public var agentLidApproval = AgentLidApproval.askWhenOpenEnded
    /// Claude Code sessions' leases use lid mode ("Keep working with the lid closed").
    public var agentSessionLid = true
    /// Agents the person chose "Always allow" for.
    public var agentLidAlwaysAllowed: [String] = []
    public var agentWindows = AgentWindowMode.automatic
    /// How long a session waiting on a permission prompt keeps the Mac awake.
    public var agentWaitingTimeout: TimeInterval = 1800

    public init() {}

    // Hand-written so that keys missing from older saved settings fall back to
    // their defaults instead of failing the whole decode, and so that "Off"
    // (nil) is written as an explicit null rather than omitted.
    private enum CodingKeys: String, CodingKey {
        case clickLevel, clickDuration, endMenuLeaseAfterSleep, allowLidOnBattery
        case lidBatteryThreshold, allBatteryThreshold, thermalCutoff
        case agentKeepAwake, agentLid, agentWindows, agentWaitingTimeout
        case agentLidApproval, agentSessionLid, agentLidAlwaysAllowed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AwakeSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            container.contains(key) ? try container.decode(T.self, forKey: key) : fallback
        }
        clickLevel = try value(.clickLevel, defaults.clickLevel)
        clickDuration = try value(.clickDuration, defaults.clickDuration)
        endMenuLeaseAfterSleep = try value(.endMenuLeaseAfterSleep, defaults.endMenuLeaseAfterSleep)
        allowLidOnBattery = try value(.allowLidOnBattery, defaults.allowLidOnBattery)
        lidBatteryThreshold = try value(.lidBatteryThreshold, defaults.lidBatteryThreshold)
        allBatteryThreshold = try value(.allBatteryThreshold, defaults.allBatteryThreshold)
        thermalCutoff = try value(.thermalCutoff, defaults.thermalCutoff)
        agentKeepAwake = try value(.agentKeepAwake, defaults.agentKeepAwake)
        agentLid = try value(.agentLid, defaults.agentLid)
        agentWindows = try value(.agentWindows, defaults.agentWindows)
        agentWaitingTimeout = try value(.agentWaitingTimeout, defaults.agentWaitingTimeout)
        agentLidApproval = try value(.agentLidApproval, defaults.agentLidApproval)
        agentSessionLid = try value(.agentSessionLid, defaults.agentSessionLid)
        agentLidAlwaysAllowed = try value(.agentLidAlwaysAllowed, defaults.agentLidAlwaysAllowed)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clickLevel, forKey: .clickLevel)
        try container.encode(clickDuration, forKey: .clickDuration)
        try container.encode(endMenuLeaseAfterSleep, forKey: .endMenuLeaseAfterSleep)
        try container.encode(allowLidOnBattery, forKey: .allowLidOnBattery)
        try container.encode(lidBatteryThreshold, forKey: .lidBatteryThreshold)
        try container.encode(allBatteryThreshold, forKey: .allBatteryThreshold)
        try container.encode(thermalCutoff, forKey: .thermalCutoff)
        try container.encode(agentKeepAwake, forKey: .agentKeepAwake)
        try container.encode(agentLid, forKey: .agentLid)
        try container.encode(agentWindows, forKey: .agentWindows)
        try container.encode(agentWaitingTimeout, forKey: .agentWaitingTimeout)
        try container.encode(agentLidApproval, forKey: .agentLidApproval)
        try container.encode(agentSessionLid, forKey: .agentSessionLid)
        try container.encode(agentLidAlwaysAllowed, forKey: .agentLidAlwaysAllowed)
    }
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

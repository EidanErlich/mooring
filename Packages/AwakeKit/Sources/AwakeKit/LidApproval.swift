/// The "Lid mode for agents" setting.
public enum AgentLidApproval: String, Codable, Sendable, CaseIterable {
    case askWhenOpenEnded, alwaysAsk, alwaysAllow, never
}

public enum LidDecision: Equatable, Sendable {
    case allow, ask, refuse
}

/// Whether an agent's lid-mode request is allowed, needs the person's approval, or is refused
/// (docs/design/2026-10-02-stage-2c1-lid-approvals-design.md, "The decision").
public enum LidApproval {
    /// `agentName == nil` means a person, who is never asked. `hasEnd` is false for a lease
    /// with no expiry and no watched process.
    public static func decide(
        setting: AgentLidApproval, agentName: String?, hasEnd: Bool, alwaysAllowed: [String]
    ) -> LidDecision {
        guard let agentName else { return .allow }
        let trusted = alwaysAllowed.contains(agentName)
        switch setting {
        case .never: return .refuse
        case .alwaysAllow: return .allow
        case .askWhenOpenEnded: return hasEnd || trusted ? .allow : .ask
        case .alwaysAsk: return trusted ? .allow : .ask
        }
    }
}

import Foundation

/// What a Claude Code hook event means for the session's lease.
public enum HookAction: Equatable, Sendable {
    case acquire, renew
    /// Set the expiry to now plus this many seconds (a session waiting on a permission prompt).
    case setExpiry(TimeInterval)
    case releaseAfter(TimeInterval)
    case releaseNow
    case ignore
    /// "Only when asked" is on, so hooks do nothing.
    case skipped

    /// The `HookResult.action` value sent back over the wire.
    public var wireName: String {
        switch self {
        case .acquire: "acquire"
        case .renew: "renew"
        case .setExpiry: "waiting"
        case .releaseAfter: "releaseAfter"
        case .releaseNow: "releaseNow"
        case .ignore: "ignore"
        case .skipped: "skipped"
        }
    }
}

/// What a hook request says about one event, as `HookPolicy` reads it.
public struct HookEvent: Equatable, Sendable {
    public var name: String
    public var notificationType: String?
    public var agentID: String?
    public var agentType: String?
    /// The number of `background_tasks` entries whose status is `running`.
    public var runningBackgroundTasks: Int?

    public init(name: String, notificationType: String? = nil, agentID: String? = nil, agentType: String? = nil,
                runningBackgroundTasks: Int? = nil) {
        self.name = name
        self.notificationType = notificationType
        self.agentID = agentID
        self.agentType = agentType
        self.runningBackgroundTasks = runningBackgroundTasks
    }
}

/// The mapping from hook events to lease actions (stage 2b spec, Lease lifecycle). Pure.
public enum HookPolicy {
    /// How long an active session's lease lasts after each event.
    public static let activeTTL: TimeInterval = 900
    /// How long a lease outlives `Stop`, for background shells and quick follow-ups.
    public static let stopGrace: TimeInterval = 120

    private static let renewEvents: Set<String> = [
        "PreToolUse", "PostToolUse", "PostToolBatch", "SubagentStart", "SubagentStop", "PreCompact"
    ]

    public static func action(_ hook: HookEvent, settings: AwakeSettings, leaseExists: Bool) -> HookAction {
        if settings.agentKeepAwake == .explicit { return .skipped }
        // An agent id with no agent type is Claude's internal helper (for example prompt suggestions after `Stop`).
        if hook.agentID != nil, hook.agentType?.isEmpty ?? true { return .ignore }
        let renewOrAcquire: HookAction = leaseExists ? .renew : .acquire
        switch hook.name {
        case _ where renewEvents.contains(hook.name):
            return renewOrAcquire
        case "UserPromptSubmit":
            return .acquire
        case "PermissionRequest":
            return .setExpiry(settings.agentWaitingTimeout)
        case "Notification":
            return hook.notificationType == "permission_prompt" ? .setExpiry(settings.agentWaitingTimeout) : .ignore
        case "Stop":
            if (hook.runningBackgroundTasks ?? 0) > 0 { return renewOrAcquire }
            return leaseExists ? .releaseAfter(stopGrace) : .ignore
        case "SessionEnd":
            return leaseExists ? .releaseNow : .ignore
        default:
            return .ignore
        }
    }
}

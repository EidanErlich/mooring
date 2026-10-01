import Foundation

/// How awake a lease keeps the Mac. Idle system sleep is always prevented while
/// any lease is live; these flags add to that (docs/SPEC.md 1.2). Lid does not
/// imply display: they are independent toggles.
public struct AwakeLevel: Codable, Hashable, Sendable {
    /// Keep the screen on.
    public var display: Bool
    /// Survive lid close (applied through the helper, stage 1c).
    public var lid: Bool

    public init(display: Bool, lid: Bool) {
        self.display = display
        self.lid = lid
    }

    public static let system = AwakeLevel(display: false, lid: false)
    public static let screenOn = AwakeLevel(display: true, lid: false)

    public func union(_ other: AwakeLevel) -> AwakeLevel {
        AwakeLevel(display: display || other.display, lid: lid || other.lid)
    }
}

public enum LeaseOwner: Codable, Hashable, Sendable {
    case menu
    case cli(pid: Int32)
    case agent(name: String)
    case mcp(client: String)
}

/// A process a lease lives as long as. The start time guards against PID reuse on restore.
public struct WatchedProcess: Codable, Hashable, Sendable {
    public var pid: Int32
    public var startTime: Date

    public init(pid: Int32, startTime: Date) {
        self.pid = pid
        self.startTime = startTime
    }
}

/// One request to stay awake. The Mac stays awake while at least one lease is live.
public struct Lease: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let owner: LeaseOwner
    public var reason: String
    public var level: AwakeLevel
    /// nil = until turned off or released.
    public var expiresAt: Date?
    public var watch: WatchedProcess?
    public var endsOnLidOpen: Bool
    public let createdAt: Date
    /// The length last granted, so a renewal without a new length can reuse it.
    /// nil for leases without an expiry and for files saved before TTLs were kept.
    public var ttl: TimeInterval?

    public init(
        id: String, owner: LeaseOwner, reason: String, level: AwakeLevel,
        expiresAt: Date?, watch: WatchedProcess? = nil, endsOnLidOpen: Bool = false, createdAt: Date,
        ttl: TimeInterval? = nil
    ) {
        self.id = id
        self.owner = owner
        self.reason = reason
        self.level = level
        self.expiresAt = expiresAt
        self.watch = watch
        self.endsOnLidOpen = endsOnLidOpen
        self.createdAt = createdAt
        self.ttl = ttl
    }

    /// Reads `leases.json` files written before `ttl` existed. Encoding stays synthesized,
    /// which omits `ttl` when it is nil.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        owner = try container.decode(LeaseOwner.self, forKey: .owner)
        reason = try container.decode(String.self, forKey: .reason)
        level = try container.decode(AwakeLevel.self, forKey: .level)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        watch = try container.decodeIfPresent(WatchedProcess.self, forKey: .watch)
        endsOnLidOpen = try container.decode(Bool.self, forKey: .endsOnLidOpen)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        ttl = try container.decodeIfPresent(TimeInterval.self, forKey: .ttl)
    }

    public func isLive(at now: Date) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt > now
    }
}

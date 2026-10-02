import Foundation

/// Who holds a lease.
public struct OwnerInfo: Codable, Sendable, Equatable {
    public var kind: String
    public var name: String

    public init(kind: String, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// One lease as the app reports it. `expiresAt` is an explicit `null` for leases that never expire.
public struct LeaseInfo: Codable, Sendable, Equatable {
    public var id: String
    public var owner: OwnerInfo
    public var reason: String
    public var level: String
    public var expiresAt: Date?
    public var watchPid: Int32?
    public var ttl: Double?
    /// True while the lease waits for a lid-mode approval. Absent on the wire from older apps, so it decodes to false.
    public var pendingApproval: Bool

    public init(id: String, owner: OwnerInfo, reason: String, level: String, expiresAt: Date?, watchPid: Int32?, ttl: Double?,
                pendingApproval: Bool) {
        self.id = id
        self.owner = owner
        self.reason = reason
        self.level = level
        self.expiresAt = expiresAt
        self.watchPid = watchPid
        self.ttl = ttl
        self.pendingApproval = pendingApproval
    }

    enum CodingKeys: String, CodingKey { case id, owner, reason, level, expiresAt, watchPid, ttl, pendingApproval }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        owner = try container.decode(OwnerInfo.self, forKey: .owner)
        reason = try container.decode(String.self, forKey: .reason)
        level = try container.decode(String.self, forKey: .level)
        expiresAt = try container.decode(Date?.self, forKey: .expiresAt)
        watchPid = try container.decodeIfPresent(Int32.self, forKey: .watchPid)
        ttl = try container.decodeIfPresent(Double.self, forKey: .ttl)
        pendingApproval = try container.decodeIfPresent(Bool.self, forKey: .pendingApproval) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(owner, forKey: .owner)
        try container.encode(reason, forKey: .reason)
        try container.encode(level, forKey: .level)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(watchPid, forKey: .watchPid)
        try container.encodeIfPresent(ttl, forKey: .ttl)
        try container.encode(pendingApproval, forKey: .pendingApproval)
    }
}

public struct AcquireResult: Codable, Sendable, Equatable {
    public var lease: LeaseInfo
    public var clamped: Bool

    public init(lease: LeaseInfo, clamped: Bool) {
        self.lease = lease
        self.clamped = clamped
    }
}

public struct ReleaseResult: Codable, Sendable, Equatable {
    public var released: Bool

    public init(released: Bool) {
        self.released = released
    }
}

/// What the app did with a hook event: `acquire`, `renew`, `waiting`, `releaseAfter`, `releaseNow`, `ignore` or `skipped`.
public struct HookResult: Codable, Sendable, Equatable {
    public var action: String

    public init(action: String) {
        self.action = action
    }
}

/// Which assertions the engine wants held right now.
public struct LevelInfo: Codable, Sendable, Equatable {
    public var system: Bool
    public var display: Bool
    public var lid: Bool

    public init(system: Bool, display: Bool, lid: Bool) {
        self.system = system
        self.display = display
        self.lid = lid
    }
}

/// `batteryPercent` is an explicit `null` on machines without a battery.
public struct PowerInfo: Codable, Sendable, Equatable {
    public var onAC: Bool
    public var batteryPercent: Int?

    public init(onAC: Bool, batteryPercent: Int?) {
        self.onAC = onAC
        self.batteryPercent = batteryPercent
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(onAC, forKey: .onAC)
        try container.encode(batteryPercent, forKey: .batteryPercent)
    }
}

/// The app's whole state for `mooring status`. `helperSleepDisabled` and `lidClosed` are explicit `null` when unknown.
public struct StatusResult: Codable, Sendable, Equatable {
    /// The dropdown's first line, for example "On · lid mode · 1h 12m left".
    public var summary: String
    public var effective: LevelInfo
    public var systemAssertion: Bool
    public var displayAssertion: Bool
    public var lidSleepDisabled: Bool
    public var helperSleepDisabled: Bool?
    public var wantsLid: Bool
    public var leases: [LeaseInfo]
    public var power: PowerInfo
    public var thermal: String
    public var lidClosed: Bool?
    public var helper: String
    public var suspensions: [String]
    /// The notification permission as the app sees it: `granted`, `denied` or `unknown`. Absent from older apps.
    public var notifications: String?
    /// The agent lid-mode setting: `ask`, `always` or `never`. Absent from older apps.
    public var agentLidApproval: String?

    public init(summary: String, effective: LevelInfo, systemAssertion: Bool, displayAssertion: Bool, lidSleepDisabled: Bool,
                helperSleepDisabled: Bool?, wantsLid: Bool, leases: [LeaseInfo], power: PowerInfo, thermal: String,
                lidClosed: Bool?, helper: String, suspensions: [String], notifications: String?, agentLidApproval: String?) {
        self.summary = summary
        self.effective = effective
        self.systemAssertion = systemAssertion
        self.displayAssertion = displayAssertion
        self.lidSleepDisabled = lidSleepDisabled
        self.helperSleepDisabled = helperSleepDisabled
        self.wantsLid = wantsLid
        self.leases = leases
        self.power = power
        self.thermal = thermal
        self.lidClosed = lidClosed
        self.helper = helper
        self.suspensions = suspensions
        self.notifications = notifications
        self.agentLidApproval = agentLidApproval
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary, forKey: .summary)
        try container.encode(effective, forKey: .effective)
        try container.encode(systemAssertion, forKey: .systemAssertion)
        try container.encode(displayAssertion, forKey: .displayAssertion)
        try container.encode(lidSleepDisabled, forKey: .lidSleepDisabled)
        try container.encode(helperSleepDisabled, forKey: .helperSleepDisabled)
        try container.encode(wantsLid, forKey: .wantsLid)
        try container.encode(leases, forKey: .leases)
        try container.encode(power, forKey: .power)
        try container.encode(thermal, forKey: .thermal)
        try container.encode(lidClosed, forKey: .lidClosed)
        try container.encode(helper, forKey: .helper)
        try container.encode(suspensions, forKey: .suspensions)
        try container.encodeIfPresent(notifications, forKey: .notifications)
        try container.encodeIfPresent(agentLidApproval, forKey: .agentLidApproval)
    }
}

/// A successful response's payload. On the wire this is the bare inner value (no tag); the shape is
/// chosen by the op of the request, so decoding goes through `WireCoding.decodeResponse(_:op:)`.
public enum ResponseResult: Encodable, Sendable, Equatable {
    case acquire(AcquireResult)
    case release(ReleaseResult)
    case status(StatusResult)
    case renew(LeaseInfo)
    case hook(HookResult)

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .acquire(let result): try result.encode(to: encoder)
        case .release(let result): try result.encode(to: encoder)
        case .status(let result): try result.encode(to: encoder)
        case .renew(let result): try result.encode(to: encoder)
        case .hook(let result): try result.encode(to: encoder)
        }
    }

    fileprivate static func decode(operation: Op, from container: KeyedDecodingContainer<Response.CodingKeys>) throws -> Self {
        switch operation {
        case .acquire: .acquire(try container.decode(AcquireResult.self, forKey: .result))
        case .release: .release(try container.decode(ReleaseResult.self, forKey: .result))
        case .status: .status(try container.decode(StatusResult.self, forKey: .result))
        case .renew: .renew(try container.decode(LeaseInfo.self, forKey: .result))
        case .hook: .hook(try container.decode(HookResult.self, forKey: .result))
        }
    }
}

public enum ErrorCode: String, Codable, Sendable, Equatable {
    case badRequest = "bad_request"
    case notFound = "not_found"
    case guardrail
    case denied
    case `internal`
}

public struct WireError: Codable, Sendable, Equatable, Error {
    public var code: ErrorCode
    public var message: String

    public init(code: ErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

// `v` and `ok` are the protocol's field names (docs/SPEC.md).
// swiftlint:disable identifier_name
/// One response line: `result` on success, `error` on failure, never both.
public struct Response: Codable, Sendable, Equatable {
    public var v: Int
    public var id: String
    public var ok: Bool
    public var result: ResponseResult?
    public var error: WireError?

    /// `decoder.userInfo` key carrying the `Op` that selects how `result` decodes.
    static let opKey = CodingUserInfoKey(rawValue: "dev.mooring.ipc.op")!

    public init(v: Int, id: String, ok: Bool, result: ResponseResult?, error: WireError?) {
        self.v = v
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
    }

    public static func success(id: String, _ result: ResponseResult) -> Response {
        Response(v: WireProtocol.version, id: id, ok: true, result: result, error: nil)
    }

    public static func failure(id: String, _ code: ErrorCode, _ message: String) -> Response {
        Response(v: WireProtocol.version, id: id, ok: false, result: nil, error: WireError(code: code, message: message))
    }

    enum CodingKeys: String, CodingKey { case v, id, ok, result, error }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decode(Int.self, forKey: .v)
        id = try container.decode(String.self, forKey: .id)
        ok = try container.decode(Bool.self, forKey: .ok)
        if ok {
            guard let op = decoder.userInfo[Self.opKey] as? Op else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "Decode a Response with WireCoding.decodeResponse(_:op:)"))
            }
            result = try ResponseResult.decode(operation: op, from: container)
            error = nil
        } else {
            result = nil
            error = try container.decode(WireError.self, forKey: .error)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(v, forKey: .v)
        try container.encode(id, forKey: .id)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
    }
}
// swiftlint:enable identifier_name

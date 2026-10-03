import Foundation

/// The operations a request can name.
public enum Op: String, Codable, Sendable, Equatable { // swiftlint:disable:this type_name
    case acquire, renew, release, status, hook, notify
}

/// What an `acquire` asks for: the plain keep-awake toggle, an anchor lease or a named lease.
public enum AcquireKind: String, Codable, Sendable, Equatable {
    case on, anchor, lease // swiftlint:disable:this identifier_name
}

/// What a `release` ends: the plain toggle or one lease.
public enum ReleaseKind: String, Codable, Sendable, Equatable {
    case off, lease
}

public struct AcquireArgs: Codable, Sendable, Equatable {
    public var kind: AcquireKind
    public var id: String?
    public var level: String?
    public var ttl: Double?
    public var watchPid: Int32?
    public var reason: String?
    public var agent: String?
    /// The MCP client's self-reported name. Only the MCP server sets it.
    public var client: String?
    /// For `on` with no `ttl`: true asks for a session with no end, instead of the menu click's duration. Absent from
    /// older clients, which keep the click duration.
    public var untilOff: Bool?

    public init(kind: AcquireKind, id: String?, level: String?, ttl: Double?, watchPid: Int32?, reason: String?, agent: String?,
                client: String? = nil, untilOff: Bool? = nil) {
        self.kind = kind
        self.id = id
        self.level = level
        self.ttl = ttl
        self.watchPid = watchPid
        self.reason = reason
        self.agent = agent
        self.client = client
        self.untilOff = untilOff
    }
}

public struct RenewArgs: Codable, Sendable, Equatable {
    public var id: String
    public var ttl: Double?

    public init(id: String, ttl: Double?) {
        self.id = id
        self.ttl = ttl
    }
}

public struct ReleaseArgs: Codable, Sendable, Equatable {
    public var kind: ReleaseKind
    public var id: String?
    public var after: Double?

    public init(kind: ReleaseKind, id: String?, after: Double?) {
        self.kind = kind
        self.id = id
        self.after = after
    }
}

/// What `mooring hook <Event>` reports about one Claude Code hook event. Only `event` and `sessionId` are required.
public struct HookArgs: Codable, Sendable, Equatable {
    public var event: String
    public var sessionId: String
    public var cwd: String?
    public var notificationType: String?
    /// Set on events from inside a subagent or an internal helper agent.
    public var agentID: String?
    public var agentType: String?
    /// The number of `background_tasks` entries whose status is `running`.
    public var runningBackgroundTasks: Int?
    public var watchPid: Int32?
    /// For `PreToolUse` of a Bash command: its `timeout` in seconds.
    public var toolTimeout: Double?

    public init(event: String, sessionId: String, cwd: String?, notificationType: String?, agentID: String?, agentType: String?,
                runningBackgroundTasks: Int?, watchPid: Int32?, toolTimeout: Double? = nil) {
        self.event = event
        self.sessionId = sessionId
        self.cwd = cwd
        self.notificationType = notificationType
        self.agentID = agentID
        self.agentType = agentType
        self.runningBackgroundTasks = runningBackgroundTasks
        self.watchPid = watchPid
        self.toolTimeout = toolTimeout
    }
}

/// What `notify` posts as a notification. `client` is set only by the MCP server.
public struct NotifyArgs: Codable, Sendable, Equatable {
    public var title: String
    public var body: String?
    public var client: String?

    public init(title: String, body: String? = nil, client: String? = nil) {
        self.title = title
        self.body = body
        self.client = client
    }
}

/// A request's arguments. On the wire this is a plain object whose fields follow the request's `op`,
/// so decoding goes through `Request`, which reads `op` first.
public enum RequestArgs: Encodable, Sendable, Equatable {
    case acquire(AcquireArgs)
    case renew(RenewArgs)
    case release(ReleaseArgs)
    case status
    case hook(HookArgs)
    case notify(NotifyArgs)

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .acquire(let args): try args.encode(to: encoder)
        case .renew(let args): try args.encode(to: encoder)
        case .release(let args): try args.encode(to: encoder)
        case .hook(let args): try args.encode(to: encoder)
        case .notify(let args): try args.encode(to: encoder)
        case .status:
            _ = encoder.container(keyedBy: EmptyKeys.self)
        }
    }

    private enum EmptyKeys: CodingKey {}
}

// `v` and `op` are the protocol's field names (docs/SPEC.md).
// swiftlint:disable identifier_name
public struct Request: Codable, Sendable, Equatable {
    public var v: Int
    public var id: String
    public var op: Op
    public var args: RequestArgs

    public init(v: Int, id: String, op: Op, args: RequestArgs) {
        self.v = v
        self.id = id
        self.op = op
        self.args = args
    }

    private enum CodingKeys: String, CodingKey { case v, id, op, args }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decode(Int.self, forKey: .v)
        id = try container.decode(String.self, forKey: .id)
        op = try container.decode(Op.self, forKey: .op)
        switch op {
        case .acquire: args = .acquire(try container.decode(AcquireArgs.self, forKey: .args))
        case .renew: args = .renew(try container.decode(RenewArgs.self, forKey: .args))
        case .release: args = .release(try container.decode(ReleaseArgs.self, forKey: .args))
        case .status: args = .status
        case .hook: args = .hook(try container.decode(HookArgs.self, forKey: .args))
        case .notify: args = .notify(try container.decode(NotifyArgs.self, forKey: .args))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(v, forKey: .v)
        try container.encode(id, forKey: .id)
        try container.encode(op, forKey: .op)
        try container.encode(args, forKey: .args)
    }
}

// swiftlint:enable identifier_name

/// Encoding and decoding of newline-delimited JSON lines.
public enum WireCoding {
    /// The longest request line the server accepts, in bytes.
    public static let maxLineBytes = 65_536

    /// Compact JSON with ISO 8601 dates, sorted keys and exactly one trailing newline.
    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// Parses one request line (with or without its trailing newline); every failure is `bad_request`.
    public static func decodeRequest(_ line: Data) -> Result<Request, WireError> {
        guard line.count <= maxLineBytes else { return .failure(WireError(code: .badRequest, message: "Request too long")) }
        var body = line
        if body.last == UInt8(ascii: "\n") { body.removeLast() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let header = try decoder.decode(VersionHeader.self, from: body)
            guard header.v == WireProtocol.version else {
                return .failure(WireError(code: .badRequest, message: "Unsupported protocol version \(header.v)"))
            }
            return .success(try decoder.decode(Request.self, from: body))
        } catch {
            return .failure(WireError(code: .badRequest, message: "Malformed request"))
        }
    }

    /// Parses a response line to the request with operation `op`, which decides the shape of `result`.
    public static func decodeResponse(_ line: Data, op: Op) throws -> Response { // swiftlint:disable:this identifier_name
        var body = line
        if body.last == UInt8(ascii: "\n") { body.removeLast() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[Response.opKey] = op
        return try decoder.decode(Response.self, from: body)
    }

    private struct VersionHeader: Decodable {
        let v: Int // swiftlint:disable:this identifier_name
    }
}

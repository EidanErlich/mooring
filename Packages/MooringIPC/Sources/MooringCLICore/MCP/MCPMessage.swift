import Foundation

/// Any JSON value, for the parts of MCP messages whose shape isn't fixed. Integers stay integers, so a request id of 7
/// is echoed as 7, not 7.0.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// `value` as JSON, with dates in ISO 8601 as the wire writes them; null when it can't be encoded.
    init(encoding value: some Encodable) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            self = .null
            return
        }
        self = json
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// One line of compact JSON with sorted keys, without a trailing newline.
    var compactText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let text = String(bytes: data, encoding: .utf8) else { return "null" }
        return text
    }
}

/// A JSON-RPC error the server answers with.
struct RPCError: Error, Equatable {
    let code: Int
    let message: String

    static let parseError = RPCError(code: -32700, message: "Parse error")
    static let invalidRequest = RPCError(code: -32600, message: "Invalid request")
    static let methodNotFound = RPCError(code: -32601, message: "Method not found")

    static func invalidParams(_ message: String) -> RPCError {
        RPCError(code: -32602, message: message)
    }
}

/// One line from the client, sorted by what it needs from the server.
enum MCPMessage: Equatable {
    /// A call that wants a reply carrying `id`.
    case request(id: JSONValue, method: String, params: JSONValue?)
    /// A call that wants no reply.
    case notification(method: String)
    /// The client's answer to a request of ours. The server sends none, so it is ignored.
    case reply

    /// The longest line the server reads, in bytes; a longer one is a parse error.
    static let maxLineBytes = 1_048_576

    static func parse(_ line: String) -> Result<MCPMessage, RPCError> {
        guard line.utf8.count <= maxLineBytes,
              let json = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            return .failure(.parseError)
        }
        guard case .object(let members) = json else { return .failure(.invalidRequest) }
        guard let method = members["method"]?.stringValue else {
            return members["result"] != nil || members["error"] != nil ? .success(.reply) : .failure(.invalidRequest)
        }
        guard let id = members["id"] else { return .success(.notification(method: method)) }
        switch id {
        case .string, .int: return .success(.request(id: id, method: method, params: members["params"]))
        default: return .failure(.invalidRequest)
        }
    }

    /// The reply line to request `id` carrying `result`, ending in a newline.
    static func resultLine(id: JSONValue, _ result: JSONValue) -> String {
        JSONValue.object(["jsonrpc": .string("2.0"), "id": id, "result": result]).compactText + "\n"
    }

    /// The error line to request `id` (null when the request couldn't be read), ending in a newline.
    static func errorLine(id: JSONValue, _ error: RPCError) -> String {
        let body = JSONValue.object(["code": .int(error.code), "message": .string(error.message)])
        return JSONValue.object(["jsonrpc": .string("2.0"), "id": id, "error": body]).compactText + "\n"
    }
}

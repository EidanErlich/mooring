import Foundation
import MooringIPC

/// The fixed tool table of `mooring mcp`, and the checks that turn a `tools/call` into a call the server can make.
enum MCPTools {
    struct Definition: Equatable {
        let name: String
        let description: String
        let inputSchema: JSONValue
    }

    /// A tool call whose arguments passed the checks.
    enum Call: Equatable {
        case keepAwake(minutes: Int, level: String, reason: String?, leaseID: String?)
        case release(leaseID: String?)
        case status
        case notify(title: String, body: String?)
    }

    enum Parsed: Equatable {
        case call(Call)
        /// Bad arguments: a tool error with this text, not a protocol error.
        case invalid(String)
        case unknownTool
    }

    static let minutesRange = 1...240
    static let levels = ["system", "display", "lid"]
    static let foreignLease = "not one of this client's leases"
    private static let badMinutes = "minutes must be a whole number from \(minutesRange.lowerBound) to \(minutesRange.upperBound)"

    static let definitions: [Definition] = [
        Definition(
            name: "keep_awake",
            description: "Keep this Mac awake for a number of minutes while you work, for example during a long build, "
                + "download or test run. Returns a lease id; pass it back as lease_id to extend that lease. "
                + "The lease also ends when this MCP server stops.",
            inputSchema: schema(required: ["minutes"], properties: [
                "minutes": .object([
                    "type": .string("integer"), "minimum": .int(minutesRange.lowerBound), "maximum": .int(minutesRange.upperBound),
                    "description": .string("How long to stay awake, in minutes.")
                ]),
                "reason": .object(["type": .string("string"), "description": .string("Why, shown in Mooring's menu.")]),
                "level": .object([
                    "type": .string("string"), "enum": .array(levels.map(JSONValue.string)), "default": .string("system"),
                    "description": .string("system keeps the Mac awake, display also keeps the screen on, "
                        + "lid also keeps it awake with the lid closed (may ask the user).")
                ]),
                "lease_id": .object([
                    "type": .string("string"),
                    "description": .string("A lease this client created, to extend it instead of making a new one.")
                ])
            ])
        ),
        Definition(
            name: "release_awake",
            description: "Let the Mac sleep again: ends one lease this client created, or all of them when lease_id is left out.",
            inputSchema: schema(required: [], properties: [
                "lease_id": .object(["type": .string("string"), "description": .string("The lease to end.")])
            ])
        ),
        Definition(
            name: "awake_status",
            description: "Whether the Mac is being kept awake, this client's leases, battery, power and thermal state.",
            inputSchema: schema(required: [], properties: [:])
        ),
        Definition(
            name: "notify",
            description: "Post a macOS notification to the user, for example when a long job finishes and they may be away.",
            inputSchema: schema(required: ["title"], properties: [
                "title": .object(["type": .string("string"), "maxLength": .int(80), "description": .string("The headline.")]),
                "body": .object(["type": .string("string"), "maxLength": .int(300), "description": .string("More detail.")])
            ])
        )
    ]

    /// The `tools/list` result.
    static var listResult: JSONValue {
        .object(["tools": .array(definitions.map { tool in
            .object(["name": .string(tool.name), "description": .string(tool.description), "inputSchema": tool.inputSchema])
        })])
    }

    /// Checks a call's arguments; missing arguments count as an empty object.
    static func parse(name: String, arguments: JSONValue?) -> Parsed {
        let args: [String: JSONValue]
        if case .object(let members)? = arguments { args = members } else { args = [:] }
        do {
            switch name {
            case "keep_awake":
                return try keepAwake(args)
            case "release_awake":
                return .call(.release(leaseID: try string("lease_id", in: args)))
            case "awake_status":
                return .call(.status)
            case "notify":
                guard let title = try string("title", in: args) else { return .invalid("title is required") }
                return .call(.notify(title: title, body: try string("body", in: args)))
            default:
                return .unknownTool
            }
        } catch let error as ArgumentError {
            return .invalid(error.message)
        } catch {
            return .invalid("\(error)")
        }
    }

    /// A tool result: one text block, and `structured` as `structuredContent` when given.
    static func result(_ text: String, structured: JSONValue? = nil, isError: Bool = false) -> JSONValue {
        var members: [String: JSONValue] = [
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(isError)
        ]
        if let structured { members["structuredContent"] = structured }
        return .object(members)
    }

    static func failure(_ text: String) -> JSONValue {
        result(text, isError: true)
    }

    private static func keepAwake(_ args: [String: JSONValue]) throws -> Parsed {
        guard let minutes = wholeNumber(args["minutes"]), minutesRange.contains(minutes) else { return .invalid(badMinutes) }
        let level = try string("level", in: args) ?? "system"
        guard levels.contains(level) else { return .invalid("unknown level '\(level)'") }
        return .call(.keepAwake(minutes: minutes, level: level, reason: try string("reason", in: args),
                                leaseID: try string("lease_id", in: args)))
    }

    private struct ArgumentError: Error {
        let message: String
    }

    private static func string(_ key: String, in args: [String: JSONValue]) throws -> String? {
        switch args[key] {
        case nil, .null?: return nil
        case .string(let value)?: return value
        default: throw ArgumentError(message: "\(key) must be a string")
        }
    }

    /// An integer, also when written with a zero fraction such as 20.0.
    private static func wholeNumber(_ value: JSONValue?) -> Int? {
        switch value {
        case .int(let number)?: return number
        case .double(let number)? where number.rounded() == number && abs(number) < 1e9: return Int(number)
        default: return nil
        }
    }

    private static func schema(required: [String], properties: [String: JSONValue]) -> JSONValue {
        var members: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty { members["required"] = .array(required.map(JSONValue.string)) }
        return .object(members)
    }
}

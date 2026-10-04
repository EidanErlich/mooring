import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

private func arguments(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

@Test func keepAwakeSchemaBoundsMinutesAndRequiresIt() throws {
    let keepAwake = try #require(MCPTools.definitions.first { $0.name == "keep_awake" })
    guard case .object(let schema) = keepAwake.inputSchema, case .object(let properties)? = schema["properties"],
          case .object(let minutes)? = properties["minutes"] else {
        Issue.record("keep_awake has no minutes property")
        return
    }
    #expect(schema["type"] == .string("object"))
    #expect(schema["required"] == .array([.string("minutes")]))
    #expect(minutes["type"] == .string("integer"))
    #expect(minutes["minimum"] == .int(1))
    #expect(minutes["maximum"] == .int(240))
    #expect(properties.keys.sorted() == ["lease_id", "level", "minutes", "reason"])
}

@Test func notifySchemaRequiresTitle() throws {
    let notify = try #require(MCPTools.definitions.first { $0.name == "notify" })
    guard case .object(let schema) = notify.inputSchema else { return }
    #expect(schema["required"] == .array([.string("title")]))
}

@Test func keepAwakeAcceptsWholeNumberWrittenAsDecimal() throws {
    let parsed = MCPTools.parse(name: "keep_awake", arguments: try arguments(#"{"minutes":20.0,"level":"display"}"#))
    #expect(parsed == .call(.keepAwake(minutes: 20, level: "display", reason: nil, leaseID: nil)))
}

@Test func keepAwakeDefaultsToSystem() throws {
    let parsed = MCPTools.parse(name: "keep_awake", arguments: try arguments(#"{"minutes":1,"reason":"tests","lease_id":"x"}"#))
    #expect(parsed == .call(.keepAwake(minutes: 1, level: "system", reason: "tests", leaseID: "x")))
}

@Test func missingArgumentsCountAsEmpty() {
    #expect(MCPTools.parse(name: "awake_status", arguments: nil) == .call(.status))
    #expect(MCPTools.parse(name: "release_awake", arguments: nil) == .call(.release(leaseID: nil)))
    #expect(MCPTools.parse(name: "keep_awake", arguments: nil) == .invalid("minutes must be a whole number from 1 to 240"))
}

@Test func wrongTypesAreToolErrors() throws {
    func parse(_ tool: String, _ json: String) throws -> MCPTools.Parsed {
        MCPTools.parse(name: tool, arguments: try arguments(json))
    }
    #expect(try parse("keep_awake", #"{"minutes":5,"reason":3}"#) == .invalid("reason must be a string"))
    #expect(try parse("release_awake", #"{"lease_id":3}"#) == .invalid("lease_id must be a string"))
    #expect(try parse("notify", #"{"title":"t","body":[]}"#) == .invalid("body must be a string"))
    #expect(try parse("notify", "[]") == .invalid("title is required"))
}

@Test func unknownToolIsNotATool() {
    #expect(MCPTools.parse(name: "read_clipboard", arguments: nil) == .unknownTool)
}

@Test func jsonValueKeepsIntegersAndStrings() throws {
    let value = try arguments(#"{"a":1,"b":1.5,"c":"x","d":null,"e":[true]}"#)
    #expect(value == .object(["a": .int(1), "b": .double(1.5), "c": .string("x"), "d": .null, "e": .array([.bool(true)])]))
    #expect(JSONValue.int(7).compactText == "7")
}

@Test func messageParsingSortsRequestsNotificationsAndReplies() {
    #expect(MCPMessage.parse(#"{"jsonrpc":"2.0","id":"a","method":"ping"}"#)
        == .success(.request(id: .string("a"), method: "ping", params: nil)))
    #expect(MCPMessage.parse(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{}}"#)
        == .success(.notification(method: "notifications/cancelled")))
    #expect(MCPMessage.parse(#"{"jsonrpc":"2.0","id":3,"result":{}}"#) == .success(.reply))
    #expect(MCPMessage.parse("[1]") == .failure(.invalidRequest))
    #expect(MCPMessage.parse(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#) == .failure(.invalidRequest))
    #expect(MCPMessage.parse("nope") == .failure(.parseError))
}

@Test func arrangeWindowsSchemaDescribesAPlacement() throws {
    let tool = try #require(MCPTools.definitions.first { $0.name == "arrange_windows" })
    guard case .object(let schema) = tool.inputSchema, case .object(let properties)? = schema["properties"],
          case .object(let placements)? = properties["placements"], case .object(let item)? = placements["items"],
          case .object(let itemProperties)? = item["properties"], case .object(let frame)? = itemProperties["frame"],
          case .object(let frameProperties)? = frame["properties"], case .object(let xBound)? = frameProperties["x"] else {
        Issue.record("arrange_windows has no placement schema")
        return
    }
    #expect(schema["required"] == .array([.string("placements")]))
    #expect(placements["type"] == .string("array"))
    #expect(placements["minItems"] == .int(1))
    #expect(placements["maxItems"] == .int(32))
    #expect(item["required"] == .array([.string("app")]))
    #expect(itemProperties.keys.sorted() == ["app", "frame", "region", "screen", "title"])
    #expect(frameProperties.keys.sorted() == ["h", "w", "x", "y"])
    #expect(xBound["minimum"] == .int(0))
    #expect(xBound["maximum"] == .int(1))
    #expect(properties.keys.sorted() == ["launch", "placements", "preview"])
}

@Test func windowToolsParseTheirArguments() throws {
    #expect(MCPTools.parse(name: "list_windows", arguments: nil) == .call(.listWindows))
    #expect(MCPTools.parse(name: "undo_arrangement", arguments: nil) == .call(.undoArrangement))
    #expect(MCPTools.parse(name: "save_layout", arguments: try arguments(#"{"name":" a "}"#)) == .call(.saveLayout(name: "a")))
    #expect(MCPTools.parse(name: "apply_layout", arguments: try arguments(#"{"name":"a"}"#)) == .call(.applyLayout(name: "a")))
    #expect(MCPTools.parse(name: "apply_layout", arguments: nil) == .invalid("name is required"))
    let json = #"{"placements":[{"app":" Safari ","region":"maximize"}]}"#
    let plan = MCPTools.parse(name: "arrange_windows", arguments: try arguments(json))
    #expect(plan == .call(.arrangeWindows(WinPlan(placements: [WinPlacement(app: "Safari", region: "maximize")]))))
    #expect(MCPTools.parse(name: "arrange_windows", arguments: nil) == .invalid("placements is required"))
    #expect(MCPTools.parse(name: "arrange_windows", arguments: try arguments("{}")) == .invalid("placements is required"))
}

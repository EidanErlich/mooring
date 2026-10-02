import Foundation
import MooringIPC
import Testing

private func object(_ line: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
}

@Test func hookRequestRoundTrips() throws {
    let args = HookArgs(event: "Notification", sessionId: "s-1", cwd: "/tmp/proj", notificationType: "permission_prompt",
                        agentID: "a1", agentType: "general-purpose", runningBackgroundTasks: 2, watchPid: 4121, toolTimeout: 1200)
    let request = Request(v: 1, id: "h1", op: .hook, args: .hook(args))
    let line = try WireCoding.encodeLine(request)
    let wireArgs = try #require(try object(line)["args"] as? [String: Any])
    #expect(wireArgs.keys.sorted() == ["agentID", "agentType", "cwd", "event", "notificationType", "runningBackgroundTasks",
                                       "sessionId", "toolTimeout", "watchPid"])
    #expect(try object(line)["op"] as? String == "hook")
    #expect(try WireCoding.decodeRequest(line).get() == request)

    let minimal = Request(v: 1, id: "h2", op: .hook, args: .hook(HookArgs(event: "Stop", sessionId: "s-1", cwd: nil,
        notificationType: nil, agentID: nil, agentType: nil, runningBackgroundTasks: nil, watchPid: nil)))
    let minimalArgs = try #require(try object(WireCoding.encodeLine(minimal))["args"] as? [String: Any])
    #expect(minimalArgs.keys.sorted() == ["event", "sessionId"])
    #expect(try WireCoding.decodeRequest(WireCoding.encodeLine(minimal)).get() == minimal)
}

@Test func hookResultDecodesByOp() throws {
    let response = Response.success(id: "h1", .hook(HookResult(action: "waiting")))
    let line = try WireCoding.encodeLine(response)
    #expect(try object(line)["result"] as? [String: String] == ["action": "waiting"])
    #expect(try WireCoding.decodeResponse(line, op: .hook) == response)
}

@Test func unknownFieldsInHookArgsAreIgnored() throws {
    let json = #"{"v":1,"id":"h","op":"hook","args":{"event":"Stop","sessionId":"s","futureField":{"x":1},"cwd":"/p"}}"#
    let request = try WireCoding.decodeRequest(Data(json.utf8)).get()
    #expect(request.args == .hook(HookArgs(event: "Stop", sessionId: "s", cwd: "/p", notificationType: nil, agentID: nil,
        agentType: nil, runningBackgroundTasks: nil, watchPid: nil)))
}

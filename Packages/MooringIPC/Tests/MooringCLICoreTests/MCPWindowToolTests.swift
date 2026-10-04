import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

private func winArrangeReply(_ results: [WinPlacementResult], to request: Request) -> Result<Response, CLIError> {
    .success(.success(id: request.id, .winArrange(WinArrangeResult(results: results, undoAvailable: true))))
}

@Test func arrangeWindowsRelaysOnePlanWithClient() async throws {
    let harness = MCPHarness()
    let arguments = #"{"placements":[{"app":"Safari","region":"left-half"},"#
        + #"{"app":"Notes","frame":{"x":0.5,"y":0,"w":0.5,"h":1},"screen":"right","title":"Todo"}],"launch":true,"preview":false}"#
    _ = await harness.run([initialize(), call(2, "arrange_windows", arguments)])
    #expect(harness.client.requests.isEmpty)
    #expect(harness.lidClient.requests.isEmpty)
    let request = try #require(harness.windowClient.requests.first)
    #expect(harness.windowClient.requests.count == 1)
    #expect(request.op == .winArrange)
    #expect(request.args == .winArrange(WinPlan(
        placements: [
            WinPlacement(app: "Safari", region: "left-half"),
            WinPlacement(app: "Notes", frame: WinFrame(x: 0.5, y: 0, w: 0.5, h: 1), screen: "right", title: "Todo")
        ],
        launch: true, preview: false, client: "claude-ai"
    )))
    #expect(harness.isError(2) == false)
    #expect(harness.text(2) == "Safari ok\nNotes ok")
    let results = try #require(harness.structured(2)?["results"] as? [[String: Any]])
    #expect(results.count == 2)
    #expect(harness.structured(2)?["undoAvailable"] as? Bool == true)
}

@Test func arrangeWindowsRejectsBadArgumentsWithoutCallingTheApp() async {
    let harness = MCPHarness()
    _ = await harness.run([
        initialize(), call(2, "arrange_windows", #"{"placements":[]}"#), call(3, "arrange_windows", "{}"),
        call(4, "arrange_windows", #"{"placements":[{"region":"left-half"}]}"#),
        call(5, "arrange_windows", #"{"placements":[{"app":"Safari"}]}"#)
    ])
    #expect(harness.allRequests.isEmpty)
    for id in 2...5 { #expect(harness.isError(id) == true) }
}

@Test func notOkPlacementsAreNotErrors() async throws {
    var harness = MCPHarness()
    harness.windowClient = ScriptedClient { request in
        winArrangeReply([
            WinPlacementResult(app: "Safari", status: .ok),
            WinPlacementResult(app: "Slack", status: .ambiguous, candidates: ["Inbox", "Drafts"],
                               reason: "matches several windows: Inbox, Drafts"),
            WinPlacementResult(app: "Zed", status: .notRunning, reason: "isn't running")
        ], to: request)
    }
    let arguments = #"{"placements":[{"app":"Safari","region":"left-half"},{"app":"Slack","region":"right-half"},"#
        + #"{"app":"Zed","region":"maximize"}]}"#
    _ = await harness.run([initialize(), call(2, "arrange_windows", arguments)])
    #expect(harness.isError(2) == false)
    let text = try #require(harness.text(2))
    #expect(text.split(separator: "\n").count == 3)
    #expect(text.contains("Slack ambiguous: matches several windows: Inbox, Drafts"))
    #expect(text.contains("Zed isn't running"))
    #expect(!text.contains("running: isn't running"))
    let results = try #require(harness.structured(2)?["results"] as? [[String: Any]])
    #expect(results.map { $0["status"] as? String } == ["ok", "ambiguous", "not_running"])
}

@Test func deniedIsError() async {
    for code in [ErrorCode.denied, .badRequest, .notFound] {
        var harness = MCPHarness()
        harness.windowClient = ScriptedClient { .success(.failure(id: $0.id, code, "Windows is off")) }
        _ = await harness.run([
            initialize(), call(2, "arrange_windows", #"{"placements":[{"app":"Safari","region":"left-half"}]}"#),
            call(3, "undo_arrangement"), call(4, "save_layout", #"{"name":"x"}"#), call(5, "apply_layout", #"{"name":"x"}"#)
        ])
        for id in 2...5 {
            #expect(harness.isError(id) == true)
            #expect(harness.text(id) == "Windows is off")
        }
    }
}

@Test func listWindowsUsesTheWindowClientAndIsErrorOnDenied() async throws {
    var harness = MCPHarness()
    harness.windowClient = ScriptedClient { .success(.failure(id: $0.id, .denied, "Windows is off. Turn it on from the menu bar.")) }
    _ = await harness.run([initialize(), call(2, "list_windows")])
    // Named as the client, so the app counts it as an agent's (and refuses it when agents are Off).
    #expect(harness.windowClient.requests.first?.args == .winList(WinListArgs(client: "claude-ai")))
    #expect(harness.client.requests.isEmpty)
    #expect(harness.isError(2) == true)
    #expect(harness.text(2) == "Windows is off. Turn it on from the menu bar.")
}

@Test func listWindowsReturnsTheListAsStructuredContent() async throws {
    var harness = MCPHarness()
    let list = WinListResult(
        apps: [WinAppInfo(name: "Safari", bundleID: "com.apple.Safari", pid: 7, windows: [])],
        screens: [WinScreenInfo(index: 0, name: "Built-in", visibleFrame: WinFrame(x: 0, y: 0, w: 1440, h: 900), position: "main")],
        regions: ["left-half"]
    )
    harness.windowClient = ScriptedClient { .success(.success(id: $0.id, .winList(list))) }
    _ = await harness.run([initialize(), call(2, "list_windows")])
    #expect(harness.isError(2) == false)
    #expect((harness.structured(2)?["apps"] as? [[String: Any]])?.count == 1)
    #expect(harness.structured(2)?["regions"] as? [String] == ["left-half"])
    #expect(harness.text(2)?.contains("Safari") == true)
}

@Test func undoArrangementSendsClientAndHandlesNothingToUndo() async throws {
    let harness = MCPHarness()
    _ = await harness.run([initialize(), call(2, "undo_arrangement")])
    #expect(harness.windowClient.requests.first?.args == .winUndo(WinUndoArgs(client: "claude-ai")))
    #expect(harness.isError(2) == false)
    #expect(harness.text(2) == "Nothing to undo")

    var restoring = MCPHarness()
    restoring.windowClient = ScriptedClient { winArrangeReply([WinPlacementResult(app: "Safari", status: .ok)], to: $0) }
    _ = await restoring.run([initialize(), call(2, "undo_arrangement")])
    #expect(restoring.isError(2) == false)
    #expect(restoring.text(2) == "Safari ok")
}

@Test func saveLayoutRelays() async throws {
    let harness = MCPHarness()
    _ = await harness.run([initialize(), call(2, "save_layout", #"{"name":"  review "}"#), call(3, "save_layout", "{}")])
    #expect(harness.windowClient.requests.map(\.args) == [.winLayout(WinLayoutArgs(action: "save", name: "review", client: "claude-ai"))])
    #expect(harness.isError(2) == false)
    #expect(harness.text(2) == "Saved review")
    #expect(harness.isError(3) == true)
}

@Test func applyLayoutRelays() async throws {
    var harness = MCPHarness()
    harness.windowClient = ScriptedClient { request in
        .success(.success(id: request.id, .winLayout(WinLayoutResult(
            names: [], arrange: WinArrangeResult(results: [WinPlacementResult(app: "Safari", status: .partial,
                                                                            frame: WinFrame(x: 0, y: 0, w: 700, h: 400))],
                                                 undoAvailable: true)
        ))))
    }
    _ = await harness.run([initialize(), call(2, "apply_layout", #"{"name":"review"}"#)])
    #expect(harness.windowClient.requests.first?.args == .winLayout(WinLayoutArgs(action: "apply", name: "review", client: "claude-ai")))
    #expect(harness.isError(2) == false)
    #expect(harness.text(2) == "Safari partial: stopped at 700x400")
    #expect((harness.structured(2)?["arrange"] as? [String: Any])?["results"] is [[String: Any]])
}

@Test func windowToolsUseTheEmptyClientBeforeInitialize() async throws {
    let harness = MCPHarness()
    _ = await harness.run([call(2, "undo_arrangement")])
    #expect(harness.windowClient.requests.first?.args == .winUndo(WinUndoArgs(client: "")))
}

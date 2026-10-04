import Foundation
import MooringIPC
import Testing

@Suite struct WinWireTests {
    private func object(_ line: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
    }

    private let plan = WinPlan(
        placements: [
            WinPlacement(app: "chrome", region: "right-half"),
            WinPlacement(app: "iterm", frame: WinFrame(x: 0, y: 0.5, w: 0.5, h: 0.5), screen: "main", title: "build")
        ],
        launch: true, preview: nil, client: "Cursor"
    )

    private let arrangeResult = WinArrangeResult(
        results: [
            WinPlacementResult(app: "chrome", status: .ok, frame: WinFrame(x: 960, y: 25, w: 960, h: 1055)),
            WinPlacementResult(app: "iterm", status: .ok, frame: WinFrame(x: 0, y: 540, w: 960, h: 540),
                               note: "was minimized, restored"),
            WinPlacementResult(app: "slack", status: .ambiguous, candidates: ["Slack — general", "Slack — random"]),
            WinPlacementResult(app: "zoom", status: .notRunning, reason: "not running")
        ],
        undoAvailable: true
    )

    @Test func eachOpRoundTrips() throws {
        let requests: [(Request, String)] = [
            (Request(v: 1, id: "a", op: .winList, args: .winList), "win.list"),
            (Request(v: 1, id: "b", op: .winArrange, args: .winArrange(plan)), "win.arrange"),
            (Request(v: 1, id: "c", op: .winUndo, args: .winUndo), "win.undo"),
            (Request(v: 1, id: "d", op: .winLayout, args: .winLayout(WinLayoutArgs(action: "save", name: "coding", client: "Zed"))),
             "win.layout")
        ]
        for (request, wireOp) in requests {
            let line = try WireCoding.encodeLine(request)
            #expect(try object(line)["op"] as? String == wireOp)
            #expect(try WireCoding.decodeRequest(line).get() == request)
        }
    }

    @Test func eachResultRoundTrips() throws {
        let screen = WinScreenInfo(index: 0, name: "Built-in Retina Display", visibleFrame: WinFrame(x: 0, y: 25, w: 1920, h: 1055),
                                   position: "main")
        let window = WinWindowInfo(id: 42, title: "Inbox", frame: WinFrame(x: 10, y: 40, w: 800, h: 600), screen: 0,
                                   minimized: false, fullScreen: false)
        let list = WinListResult(apps: [WinAppInfo(name: "Mail", bundleID: "com.apple.mail", pid: 501, windows: [window])],
                                 screens: [screen], regions: ["left-half", "maximize"])
        let responses: [(Op, Response)] = [
            (.winList, .success(id: "1", .winList(list))),
            (.winArrange, .success(id: "2", .winArrange(arrangeResult))),
            (.winUndo, .success(id: "3", .winUndo(WinArrangeResult(results: [], undoAvailable: false)))),
            (.winLayout, .success(id: "4", .winLayout(WinLayoutResult(names: ["coding"], arrange: arrangeResult))))
        ]
        for (operation, response) in responses {
            #expect(try WireCoding.decodeResponse(WireCoding.encodeLine(response), op: operation) == response)
        }
    }

    @Test func statusesUseSnakeCaseOnTheWire() throws {
        let line = try WireCoding.encodeLine(Response.success(id: "s", .winArrange(arrangeResult)))
        let result = try #require(try object(line)["result"] as? [String: Any])
        let statuses = try #require(result["results"] as? [[String: Any]]).compactMap { $0["status"] as? String }
        #expect(statuses == ["ok", "ok", "ambiguous", "not_running"])
        #expect(WinStatus.notFound.rawValue == "not_found")
    }

    @Test func winUndoHasNoArgs() throws {
        let line = try WireCoding.encodeLine(Request(v: 1, id: "u", op: .winUndo, args: .winUndo))
        #expect((try object(line)["args"] as? [String: Any])?.isEmpty == true)

        for json in [#"{"v":1,"id":"u","op":"win.undo","args":{}}"#, #"{"v":1,"id":"u","op":"win.undo"}"#,
                     #"{"v":1,"id":"u","op":"win.undo","args":{"stray":1}}"#] {
            #expect(try WireCoding.decodeRequest(Data(json.utf8)).get() == Request(v: 1, id: "u", op: .winUndo, args: .winUndo))
        }
    }

    @Test func nilPlacementFieldsAreOmitted() throws {
        let request = Request(v: 1, id: "p", op: .winArrange,
                              args: .winArrange(WinPlan(placements: [WinPlacement(app: "chrome", region: "left-half")])))
        let args = try #require(try object(WireCoding.encodeLine(request))["args"] as? [String: Any])
        #expect(args.keys.sorted() == ["placements"])
        let placement = try #require((args["placements"] as? [[String: Any]])?.first)
        #expect(placement.keys.sorted() == ["app", "region"])
    }

    @Test func decodingIsLenient() throws {
        let arrange = #"{"v":1,"id":"a","op":"win.arrange","args":{"placements":"#
            + #"[{"app":"chrome","region":"left-half","extra":true}],"future":1}}"#
        guard case .winArrange(let plan) = try WireCoding.decodeRequest(Data(arrange.utf8)).get().args else {
            Issue.record("expected a plan")
            return
        }
        #expect(plan == WinPlan(placements: [WinPlacement(app: "chrome", region: "left-half")]))
        #expect(plan.launch == nil && plan.preview == nil && plan.client == nil)

        let layout = #"{"v":1,"id":"l","op":"win.layout","args":{"action":"list"}}"#
        #expect(try WireCoding.decodeRequest(Data(layout.utf8)).get().args == .winLayout(WinLayoutArgs(action: "list")))

        let older = #"{"v":1,"id":"r","ok":true,"result":{"results":[{"app":"chrome","status":"ok"}]}}"#
        let arranged = try WireCoding.decodeResponse(Data(older.utf8), op: .winArrange)
        #expect(arranged.result == .winArrange(WinArrangeResult(results: [WinPlacementResult(app: "chrome", status: .ok)],
                                                                undoAvailable: false)))

        let bareList = #"{"v":1,"id":"r","ok":true,"result":{"apps":[],"screens":[],"later":"x"}}"#
        #expect(try WireCoding.decodeResponse(Data(bareList.utf8), op: .winList).result
            == .winList(WinListResult(apps: [], screens: [], regions: [])))

        let bareLayout = #"{"v":1,"id":"r","ok":true,"result":{}}"#
        #expect(try WireCoding.decodeResponse(Data(bareLayout.utf8), op: .winLayout).result
            == .winLayout(WinLayoutResult(names: [], arrange: nil)))
    }
}

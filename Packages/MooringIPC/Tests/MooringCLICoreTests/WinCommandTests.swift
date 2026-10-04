import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

private func arranged(_ results: [WinPlacementResult], undoAvailable: Bool = true) -> Response {
    .success(id: "r", .winArrange(WinArrangeResult(results: results, undoAvailable: undoAvailable)))
}

private func okResult(_ app: String, note: String? = nil) -> WinPlacementResult {
    WinPlacementResult(app: app, status: .ok, frame: WinFrame(x: 0, y: 0, w: 100, h: 100), note: note)
}

private func plan(of request: Request?) -> WinPlan? {
    guard case .winArrange(let plan)? = request?.args else { return nil }
    return plan
}

private func planJSON(_ text: String) -> Data { Data(text.utf8) }

// MARK: - Parsing

@Test func parsesAppRegionScreen() async {
    let harness = Harness(windowClient: RecordingClient(reply: .success(arranged([okResult("chrome"), okResult("iterm")]))))
    let code = await harness.run(["win", "arrange", "chrome=right-half", "iterm=bottom-left@left", "Visual Studio Code=maximize@1"])
    #expect(code == 0)
    let sent = plan(of: harness.windowClient.lastRequest)
    #expect(sent?.placements == [
        WinPlacement(app: "chrome", region: "right-half"),
        WinPlacement(app: "iterm", region: "bottom-left", screen: "left"),
        WinPlacement(app: "Visual Studio Code", region: "maximize", screen: "1")
    ])
    #expect(sent?.launch == nil)
    #expect(sent?.preview == nil)
    #expect(sent?.client == nil)
    #expect(harness.windowClient.lastRequest?.op == .winArrange)
}

@Test func parsesFrameFractions() async {
    let harness = Harness(windowClient: RecordingClient(reply: .success(arranged([okResult("slack")]))))
    let code = await harness.run(["win", "arrange", "slack=0,0.25,0.5,0.75@right", "--launch", "--preview"])
    #expect(code == 0)
    let sent = plan(of: harness.windowClient.lastRequest)
    #expect(sent?.placements == [WinPlacement(app: "slack", frame: WinFrame(x: 0, y: 0.25, w: 0.5, h: 0.75), screen: "right")])
    #expect(sent?.launch == true)
    #expect(sent?.preview == true)
}

@Test func planFromStdin() async {
    let json = """
        {"placements":[{"app":"chrome","region":"left-half","title":"Inbox"},
        {"app":"iterm","frame":{"x":0,"y":0,"w":1,"h":0.5}}],"launch":true,"client":"spoof"}
        """
    let harness = Harness(windowClient: RecordingClient(reply: .success(arranged([okResult("chrome"), okResult("iterm")]))),
                          input: planJSON(json))
    let code = await harness.run(["win", "arrange", "--plan", "-"])
    #expect(code == 0)
    let sent = plan(of: harness.windowClient.lastRequest)
    #expect(sent?.placements.map(\.app) == ["chrome", "iterm"])
    #expect(sent?.placements.first?.title == "Inbox")
    #expect(sent?.placements.last?.frame == WinFrame(x: 0, y: 0, w: 1, h: 0.5))
    #expect(sent?.launch == true)
    #expect(sent?.client == nil)
}

@Test func planFromFile() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let path = folder + "/plan.json"
    try planJSON(#"{"placements":[{"app":"chrome","region":"left-half"}]}"#).write(to: URL(fileURLWithPath: path))
    let harness = Harness(windowClient: RecordingClient(reply: .success(arranged([okResult("chrome")]))))
    #expect(await harness.run(["win", "arrange", "--plan", path, "--preview"]) == 0)
    #expect(plan(of: harness.windowClient.lastRequest)?.preview == true)
}

@Test func doSendsAOnePlacementPlan() async {
    let harness = Harness(windowClient: RecordingClient(reply: .success(arranged([okResult("chrome")]))))
    #expect(await harness.run(["win", "do", "left-half"]) == 0)
    #expect(plan(of: harness.windowClient.lastRequest)?.placements == [WinPlacement(app: "@frontmost", region: "left-half")])
    #expect(await harness.run(["win", "do", "maximize", "--app", "chrome", "--screen", "right"]) == 0)
    #expect(plan(of: harness.windowClient.lastRequest)?.placements == [WinPlacement(app: "chrome", region: "maximize", screen: "right")])
}

// MARK: - Exit codes

@Test func exitZeroWhenAllOk() async {
    let harness = Harness(windowClient: RecordingClient(reply: .success(arranged([okResult("chrome"), okResult("iterm")]))))
    #expect(await harness.run(["win", "arrange", "chrome=left-half", "iterm=right-half"]) == 0)
}

@Test func exitTwoWhenAnyNotOk() async {
    let results = [okResult("chrome"), WinPlacementResult(app: "slack", status: .ambiguous, candidates: ["A", "B"])]
    let harness = Harness(windowClient: RecordingClient(reply: .success(arranged(results))))
    #expect(await harness.run(["win", "arrange", "chrome=left-half", "slack=right-half"]) == 2)
    #expect(harness.capture.stdout.contains("slack ambiguous"))

    let off = "Windows is off. Turn it on in Mooring (Windows › Turn On…)."
    let denied = Harness(windowClient: RecordingClient(reply: .success(.failure(id: "r", .denied, off))))
    #expect(await denied.run(["win", "arrange", "chrome=left-half"]) == 2)
    #expect(denied.capture.stderr.contains("Windows is off"))
}

@Test func exitOneForBadPlan() async {
    let harness = Harness(input: planJSON("{not json"))
    #expect(await harness.run(["win", "arrange", "--plan", "-"]) == 1)
    #expect(harness.capture.stderr.contains("plan"))

    let empty = Harness(input: planJSON(#"{"placements":[]}"#))
    #expect(await empty.run(["win", "arrange", "--plan", "-"]) == 1)
    #expect(empty.capture.stderr.contains("at least one placement"))

    let both = Harness(input: planJSON(#"{"placements":[{"app":"a","region":"maximize","frame":{"x":0,"y":0,"w":1,"h":1}}]}"#))
    #expect(await both.run(["win", "arrange", "--plan", "-"]) == 1)

    for arguments in [
        ["win", "arrange"], ["win", "arrange", "chrome"], ["win", "arrange", "chrome="], ["win", "arrange", "=left-half"],
        ["win", "arrange", "a=1,2,3"], ["win", "arrange", "a=0,0,x,1"], ["win", "arrange", "a=left-half@"],
        ["win", "arrange", "a=left-half", "--plan", "-"], ["win", "arrange", "--plan", "/nowhere/plan.json"]
    ] {
        let usage = Harness()
        #expect(await usage.run(arguments) == 1, "\(arguments)")
        #expect(usage.windowClient.requests.isEmpty)
        #expect(!usage.capture.stderr.isEmpty, "\(arguments)")
    }
}

@Test func unreachableAppExitsThree() async {
    let harness = Harness(windowClient: RecordingClient(reply: .failure(.unreachable)))
    #expect(await harness.run(["win", "arrange", "chrome=left-half"]) == 3)
}

// MARK: - Output

@Test func humanArrangeLine() async {
    let results = [
        okResult("chrome"),
        okResult("iterm", note: "was minimized, restored"),
        WinPlacementResult(app: "slack", status: .ambiguous, candidates: ["Inbox", "Drafts"],
                           reason: "matches several windows: Inbox, Drafts"),
        WinPlacementResult(app: "code", status: .ambiguous, candidates: ["Visual Studio Code", "Xcode"],
                           reason: "matches several apps: Visual Studio Code, Xcode"),
        WinPlacementResult(app: "notes", status: .notRunning, reason: "isn't running"),
        WinPlacementResult(app: "spotify", status: .notRunning, reason: "couldn't find it to open"),
        WinPlacementResult(app: "mail", status: .partial, frame: WinFrame(x: 0, y: 0, w: 640, h: 480))
    ]
    let harness = Harness(windowClient: RecordingClient(reply: .success(arranged(results))))
    _ = await harness.run(["win", "arrange", "chrome=left-half"])
    #expect(harness.capture.stdout == """
        chrome ok
        iterm ok (was minimized, restored)
        slack ambiguous: matches several windows: Inbox, Drafts
        code ambiguous: matches several apps: Visual Studio Code, Xcode
        notes isn't running
        spotify isn't running: couldn't find it to open
        mail partial: stopped at 640x480

        """)
}

@Test func arrangeJSONPrintsTheResult() async throws {
    let harness = Harness(windowClient: RecordingClient(reply: .success(arranged([okResult("chrome")]))))
    #expect(await harness.run(["win", "arrange", "chrome=left-half", "--json"]) == 0)
    let object = try #require(try JSONSerialization.jsonObject(with: Data(harness.capture.stdout.utf8)) as? [String: Any])
    #expect((object["results"] as? [[String: Any]])?.count == 1)
}

@Test func undoNothingSays() async {
    let harness = Harness(windowClient: RecordingClient(reply: .success(.failure(id: "r", .notFound, "Nothing to undo"))))
    #expect(await harness.run(["win", "undo"]) == 1)
    #expect(harness.capture.stderr == "mooring: Nothing to undo\n")

    let nothing = Response.success(id: "r", .winUndo(WinArrangeResult(results: [], undoAvailable: false)))
    let empty = Harness(windowClient: RecordingClient(reply: .success(nothing)))
    #expect(await empty.run(["win", "undo"]) == 1)
    #expect(empty.capture.stderr == "mooring: Nothing to undo\n")
}

@Test func undoPrintsWhatWasReverted() async {
    let reply = Response.success(id: "r", .winUndo(WinArrangeResult(results: [okResult("chrome")], undoAvailable: false)))
    let harness = Harness(windowClient: RecordingClient(reply: .success(reply)))
    #expect(await harness.run(["win", "undo"]) == 0)
    #expect(harness.capture.stdout == "chrome ok\n")
    #expect(harness.windowClient.lastRequest?.op == .winUndo)
}

private func layoutReply(_ names: [String], arrange: WinArrangeResult? = nil) -> Response {
    .success(id: "r", .winLayout(WinLayoutResult(names: names, arrange: arrange)))
}

@Test func layoutListPrintsNames() async {
    let harness = Harness(client: RecordingClient(reply: .success(layoutReply(["coding", "writing"]))))
    #expect(await harness.run(["win", "layout", "list"]) == 0)
    #expect(harness.capture.stdout == "coding\nwriting\n")
    guard case .winLayout(let args)? = harness.client.lastRequest?.args else { Issue.record("not a layout request"); return }
    #expect(args == WinLayoutArgs(action: "list"))
    #expect(harness.windowClient.requests.isEmpty)

    let none = Harness(client: RecordingClient(reply: .success(layoutReply([]))))
    #expect(await none.run(["win", "layout", "list"]) == 0)
    #expect(none.capture.stdout == "No saved layouts\n")
}

@Test func layoutActionsUseTheLongClient() async {
    let harness = Harness(windowClient: RecordingClient(reply: .success(layoutReply(["coding"]))))
    #expect(await harness.run(["win", "layout", "save", "coding"]) == 0)
    #expect(harness.capture.stdout == "Saved coding\n")
    #expect(await harness.run(["win", "layout", "delete", "coding"]) == 0)
    #expect(harness.windowClient.requests.count == 2)
    guard case .winLayout(let args)? = harness.windowClient.lastRequest?.args else { Issue.record("not a layout request"); return }
    #expect(args == WinLayoutArgs(action: "delete", name: "coding"))
    #expect(harness.client.requests.isEmpty)
}

@Test func layoutApplyReportsPlacementsAndExitCode() async {
    let results = [okResult("chrome"), WinPlacementResult(app: "slack", status: .notFound, reason: "has no windows")]
    let applied = layoutReply(["coding"], arrange: WinArrangeResult(results: results, undoAvailable: true))
    let harness = Harness(windowClient: RecordingClient(reply: .success(applied)))
    #expect(await harness.run(["win", "layout", "apply", "coding"]) == 2)
    #expect(harness.capture.stdout == "chrome ok\nslack not found: has no windows\n")
}

@Test func layoutNeedsAName() async {
    let harness = Harness()
    #expect(await harness.run(["win", "layout", "save"]) == 1)
    #expect(harness.windowClient.requests.isEmpty)
}

@Test func listGroupsWindowsByApp() async {
    let result = WinListResult(
        apps: [
            WinAppInfo(name: "Safari", bundleID: "com.apple.Safari", pid: 10, windows: [
                WinWindowInfo(id: 1, title: "Home", frame: WinFrame(x: 0, y: 25, w: 1440, h: 875), screen: 0,
                              minimized: false, fullScreen: false),
                WinWindowInfo(id: 2, title: "Docs", frame: WinFrame(x: 100, y: 100, w: 800, h: 600), screen: 1,
                              minimized: true, fullScreen: false)
            ]),
            WinAppInfo(name: "Finder", bundleID: nil, pid: 11, windows: [])
        ],
        screens: [WinScreenInfo(index: 0, name: "Built-in", visibleFrame: WinFrame(x: 0, y: 25, w: 1440, h: 875), position: "main")],
        regions: ["left-half", "maximize"])
    let harness = Harness(windowClient: RecordingClient(reply: .success(.success(id: "r", .winList(result)))))
    #expect(await harness.run(["win", "list"]) == 0)
    #expect(harness.capture.stdout == """
        Safari
          Home · 0,25 1440x875 · screen 0
          Docs · 100,100 800x600 · screen 1 · minimized
        Finder
          no windows
        Screens
          0 Built-in (main) · 0,25 1440x875

        """)
    #expect(harness.windowClient.lastRequest?.op == .winList)

    let regions = Harness(windowClient: RecordingClient(reply: .success(.success(id: "r", .winList(result)))))
    #expect(await regions.run(["win", "list-regions"]) == 0)
    #expect(regions.capture.stdout == "left-half\nmaximize\n")
}

/// Listing makes several Accessibility calls per app, so a few hung apps can outlast the normal client's timeout.
@Test func listUsesTheWindowClient() async {
    let harness = Harness()
    _ = await harness.run(["win", "list", "--json"])
    #expect(harness.windowClient.requests.count == 1)
    #expect(harness.client.requests.isEmpty)
}

// MARK: - Timeouts

@Test func usesLongTimeoutForArrange() async {
    let harness = Harness(windowClient: RecordingClient(reply: .success(arranged([okResult("chrome")]))))
    _ = await harness.run(["win", "arrange", "chrome=left-half"])
    _ = await harness.run(["win", "do", "maximize"])
    _ = await harness.run(["win", "undo"])
    #expect(harness.windowClient.requests.map(\.op) == [.winArrange, .winArrange, .winUndo])
    #expect(harness.client.requests.isEmpty)
    #expect(harness.lidClient.requests.isEmpty)
}

import CoreGraphics
import Foundation
import MooringIPC
import Testing
import WindowKit
@testable import Mooring

/// The Arranger over `FakeWindowSystem`: main screen at the origin, a second screen to its left at negative x.
@MainActor
struct ArrangerTests {
    let fake: FakeWindowSystem
    let arranger: Arranger
    let layoutsURL: URL

    init() {
        self.init(screens: [WindowFixture.main, WindowFixture.left])
    }

    init(screens: [WSScreen]) {
        fake = WindowFixture.system(screens: screens)
        layoutsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArrangerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("layouts.json")
        arranger = Arranger(system: fake, layoutsURL: layoutsURL, locateApp: Self.locate,
                            launchTimeout: .seconds(2), pollInterval: .milliseconds(10))
    }

    /// Only Spotify can be found to open.
    static func locate(_ query: String) -> String? {
        ["spotify": "com.spotify.client", "com.spotify.client": "com.spotify.client"][query.lowercased()]
    }

    func arrange(_ placements: WinPlacement..., launch: Bool? = nil, preview: Bool? = nil) async -> [WinPlacementResult] {
        await arranger.arrange(WinPlan(placements: placements, launch: launch, preview: preview)).results
    }

    func frame(_ id: CGWindowID) -> CGRect? {
        fake.window(id)?.frame
    }

    var moves: [String] {
        fake.calls.filter { $0.hasPrefix("move") || $0.hasPrefix("apply") }
    }

    // MARK: Matching

    @Test func exactNameMatches() {
        let apps = WindowFixture.apps()
        #expect(AppMatcher.match("slack", in: apps) == .one(apps[5]))
        #expect(AppMatcher.match("GOOGLE CHROME", in: apps) == .one(apps[1]))
        #expect(AppMatcher.match("Xcode", in: apps) == .one(apps[7]))
    }

    @Test func bundleIDMatches() {
        let apps = WindowFixture.apps()
        #expect(AppMatcher.match("com.googlecode.iterm2", in: apps) == .one(apps[2]))
        #expect(AppMatcher.match("COM.MICROSOFT.VSCODE", in: apps) == .one(apps[6]))
    }

    @Test func fuzzyPrefixMatches() {
        let apps = WindowFixture.apps()
        #expect(AppMatcher.match("iterm", in: apps) == .one(apps[2]))
        #expect(AppMatcher.match("visual", in: apps) == .one(apps[6]))
        #expect(AppMatcher.match("chrome", in: apps) == .one(apps[1]))
        #expect(AppMatcher.match("slackmac", in: apps) == .one(apps[5]))
        #expect(AppMatcher.match("spotify", in: apps) == .none)
    }

    @Test func codeIsAmbiguousBetweenVSCodeAndXcode() async {
        let apps = WindowFixture.apps()
        #expect(AppMatcher.match("code", in: apps) == .ambiguous([apps[6], apps[7]]))

        let results = await arrange(WinPlacement(app: "code", region: "left-half"))
        #expect(results == [WinPlacementResult(app: "code", status: .ambiguous, candidates: ["Visual Studio Code", "Xcode"],
                                               reason: "matches several apps: Visual Studio Code, Xcode")])
        #expect(moves.isEmpty)
    }

    // MARK: Windows

    @Test func twoWindowsWithoutTitleUsesFrontmost() async {
        let results = await arrange(WinPlacement(app: "chrome", region: "right-half"))
        let expected = CGRect(x: 720, y: 25, width: 720, height: 875)
        #expect(results == [WinPlacementResult(app: "chrome", status: .ok, frame: WinFrame(expected))])
        #expect(frame(WindowFixture.chromeInbox) == expected)
        #expect(frame(WindowFixture.chromeDocs) == CGRect(x: 200, y: 150, width: 800, height: 600))
    }

    @Test func titlePicksWindow() async {
        let results = await arrange(WinPlacement(app: "chrome", region: "left-half", title: "DOCS"))
        #expect(results.map(\.status) == [.ok])
        #expect(frame(WindowFixture.chromeDocs) == CGRect(x: 0, y: 25, width: 720, height: 875))
        #expect(frame(WindowFixture.chromeInbox) == CGRect(x: 100, y: 100, width: 800, height: 600))

        let missing = await arrange(WinPlacement(app: "chrome", region: "left-half", title: "calendar"))
        #expect(missing == [WinPlacementResult(app: "chrome", status: .notFound, reason: "no window titled “calendar”")])
    }

    @Test func titleMatchingTwoIsAmbiguous() async {
        let results = await arrange(WinPlacement(app: "chrome", region: "left-half", title: "google"))
        #expect(results == [WinPlacementResult(app: "chrome", status: .ambiguous,
                                               candidates: ["Inbox – Mail – Google", "Docs – Google"],
                                               reason: "matches several windows: Inbox – Mail – Google, Docs – Google")])
        #expect(moves.isEmpty)
    }

    // MARK: Screens

    @Test func regionOnMainScreen() async {
        let results = await arrange(WinPlacement(app: "slack", region: "left-half", screen: "main"))
        #expect(results.map(\.status) == [.ok])
        #expect(fake.calls.contains("apply left-half \(WindowFixture.slackMain) 0"))
        #expect(frame(WindowFixture.slackMain) == CGRect(x: 0, y: 25, width: 720, height: 875))
    }

    @Test func regionOnLeftScreen() async {
        let results = await arrange(WinPlacement(app: "vscode", region: "right-half", screen: "left"),
                                    WinPlacement(app: "chrome", region: "left-half", screen: "1"))
        #expect(results.map(\.status) == [.ok, .ok])
        #expect(frame(WindowFixture.vscodeMain) == CGRect(x: -960, y: -155, width: 960, height: 1055))
        #expect(frame(WindowFixture.chromeInbox) == CGRect(x: -1920, y: -155, width: 960, height: 1055))

        // No screen given: the window's own screen (Slack is on the left one).
        _ = await arrange(WinPlacement(app: "slack", region: "maximize"))
        #expect(frame(WindowFixture.slackMain) == WindowFixture.left.visibleFrame)
    }

    @Test func leftWithOneScreenFails() async {
        let single = ArrangerTests(screens: [WindowFixture.main])
        let results = await single.arrange(WinPlacement(app: "slack", region: "left-half", screen: "left"),
                                           WinPlacement(app: "chrome", region: "left-half", screen: "right"))
        #expect(results == [WinPlacementResult(app: "slack", status: .failed, reason: "no screen to the left"),
                            WinPlacementResult(app: "chrome", status: .failed, reason: "no screen to the right")])
        #expect(single.moves.isEmpty)
    }

    @Test func indexOutOfRangeFails() async {
        let results = await arrange(WinPlacement(app: "slack", region: "left-half", screen: "2"),
                                    WinPlacement(app: "chrome", region: "left-half", screen: "top"))
        #expect(results == [WinPlacementResult(app: "slack", status: .failed, reason: "no screen 2"),
                            WinPlacementResult(app: "chrome", status: .failed,
                                               reason: "unknown screen “top” (use main, left, right or an index)")])
        #expect(moves.isEmpty)
    }

    @Test func fractionalFrame() async {
        // Fractions of the visible area, origin top left, on the negative-x screen.
        let results = await arrange(WinPlacement(app: "chrome", frame: WinFrame(x: 0.25, y: 0, w: 0.5, h: 1), screen: "left"),
                                    WinPlacement(app: "xcode", frame: WinFrame(x: 0, y: 0.5, w: 1, h: 0.5)))
        let chrome = CGRect(x: -1440, y: -155, width: 960, height: 1055)
        let xcode = CGRect(x: -1920, y: 372.5, width: 1920, height: 527.5)
        #expect(results == [WinPlacementResult(app: "chrome", status: .ok, frame: WinFrame(chrome)),
                            WinPlacementResult(app: "xcode", status: .ok, frame: WinFrame(xcode))])
        #expect(frame(WindowFixture.chromeInbox) == chrome)
        #expect(frame(WindowFixture.xcodeMain) == xcode)
    }

    @Test func unknownRegionFails() async {
        let results = await arrange(WinPlacement(app: "slack", region: "sideways"))
        #expect(results == [WinPlacementResult(app: "slack", status: .failed, reason: "unknown region “sideways”")])
        #expect(moves.isEmpty)
    }

    // MARK: Window states

    @Test func minimizedIsRestoredWithNote() async {
        let results = await arrange(WinPlacement(app: "iterm", region: "bottom-left", screen: "main"))
        let expected = CGRect(x: 0, y: 462.5, width: 720, height: 437.5)
        #expect(results == [WinPlacementResult(app: "iterm", status: .ok, frame: WinFrame(expected),
                                               note: "was minimized, restored")])
        let shell = WindowFixture.itermShell
        #expect(fake.calls.firstIndex(of: "restore \(shell)")! < fake.calls.firstIndex(of: "apply bottom-left \(shell) 0")!)
        #expect(fake.window(shell)?.minimized == false)
    }

    @Test func fullScreenFails() async {
        let results = await arrange(WinPlacement(app: "keynote", region: "left-half"))
        #expect(results == [WinPlacementResult(app: "keynote", status: .failed, reason: "is full screen")])
        #expect(moves.isEmpty)
    }

    @Test func minimumSizeIsPartial() async {
        fake.minimumWidth[WindowFixture.slack] = 900
        let results = await arrange(WinPlacement(app: "slack", region: "left-half", screen: "main"),
                                    WinPlacement(app: "vscode", frame: WinFrame(x: 0, y: 0, w: 0.5, h: 1)))
        #expect(results == [
            WinPlacementResult(app: "slack", status: .partial, frame: WinFrame(x: 0, y: 25, w: 900, h: 875)),
            WinPlacementResult(app: "vscode", status: .ok, frame: WinFrame(x: 0, y: 25, w: 720, h: 875))
        ])

        // Within 2 pt is still ok.
        fake.minimumWidth[WindowFixture.vscode] = 722
        let close = await arrange(WinPlacement(app: "vscode", frame: WinFrame(x: 0, y: 0, w: 0.5, h: 1)))
        #expect(close.map(\.status) == [.ok])
    }

    @Test func failedMoveIsReported() async {
        fake.failingMoves = [WindowFixture.slackMain]
        let results = await arrange(WinPlacement(app: "slack", region: "left-half"))
        #expect(results == [WinPlacementResult(app: "slack", status: .failed, reason: "couldn't move the window")])
        #expect(await arranger.undo() == nil)
    }

    // MARK: Launching

    @Test func notRunningWithoutLaunch() async {
        let results = await arrange(WinPlacement(app: "spotify", region: "left-half"))
        #expect(results == [WinPlacementResult(app: "spotify", status: .notRunning, reason: "isn't running")])
        #expect(fake.calls.isEmpty)
    }

    @Test func launchThenPlaces() async {
        let spotify = WindowFixture.app("Spotify", "com.spotify.client", 201, [
            WindowFixture.window(2011, 201, "Spotify Premium", CGRect(x: 10, y: 40, width: 500, height: 500))
        ])
        fake.launchable["com.spotify.client"] = (spotify, .milliseconds(50))
        let results = await arrange(WinPlacement(app: "spotify", region: "right-half", screen: "main"),
                                    WinPlacement(app: "chrome", region: "left-half", screen: "main"), launch: true)
        #expect(results == [
            WinPlacementResult(app: "spotify", status: .ok, frame: WinFrame(x: 720, y: 25, w: 720, h: 875), note: "launched"),
            WinPlacementResult(app: "chrome", status: .ok, frame: WinFrame(x: 0, y: 25, w: 720, h: 875))
        ])
        #expect(fake.calls.filter { $0.hasPrefix("launch") } == ["launch com.spotify.client"])

        // Nothing found to open, or nothing appears in time.
        let missing = await arrange(WinPlacement(app: "nonesuch", region: "left-half"), launch: true)
        #expect(missing == [WinPlacementResult(app: "nonesuch", status: .notRunning, reason: "couldn't find it to open")])
    }

    @Test func launchThatNeverOpensIsNotRunning() async {
        let quick = Arranger(system: fake, layoutsURL: layoutsURL, locateApp: Self.locate,
                             launchTimeout: .milliseconds(50), pollInterval: .milliseconds(10))
        let spotify = WindowFixture.app("Spotify", "com.spotify.client", 201, [
            WindowFixture.window(2011, 201, "Spotify", CGRect(x: 10, y: 40, width: 500, height: 500))
        ])
        fake.launchable["com.spotify.client"] = (spotify, .seconds(5))
        let results = await quick.arrange(WinPlan(placements: [WinPlacement(app: "spotify", region: "left-half")],
                                                  launch: true)).results
        #expect(results == [WinPlacementResult(app: "spotify", status: .notRunning, reason: "didn't open in time")])
    }

    // MARK: Plans

    @Test func partialPlanAppliesTheRest() async {
        fake.failingMoves = [WindowFixture.slackMain]
        let results = await arrange(WinPlacement(app: "chrome", region: "right-half", screen: "main"),
                                    WinPlacement(app: "spotify", region: "left-half"),
                                    WinPlacement(app: "iterm", region: "bottom-left", screen: "main"),
                                    WinPlacement(app: "slack", region: "top-left"))
        #expect(results.map(\.status) == [.ok, .notRunning, .ok, .failed])
        #expect(frame(WindowFixture.chromeInbox) == CGRect(x: 720, y: 25, width: 720, height: 875))

        let undone = await arranger.undo()
        #expect(undone?.results.map(\.app) == ["chrome", "iterm"])
        #expect(undone?.results.map(\.status) == [.ok, .ok])
        #expect(frame(WindowFixture.chromeInbox) == CGRect(x: 100, y: 100, width: 800, height: 600))
        #expect(frame(WindowFixture.itermShell) == CGRect(x: 300, y: 300, width: 700, height: 400))
        #expect(frame(WindowFixture.slackMain) == CGRect(x: -1800, y: -100, width: 1000, height: 700))
    }

    @Test func previewCalledBeforeMove() async {
        _ = await arrange(WinPlacement(app: "chrome", region: "right-half", screen: "main"),
                          WinPlacement(app: "slack", frame: WinFrame(x: 0, y: 0, w: 0.5, h: 0.5), screen: "main"),
                          preview: true)
        let acting = fake.calls.filter { !$0.hasPrefix("target") }
        #expect(acting == ["preview 0", "apply right-half \(WindowFixture.chromeInbox) 0", "preview 0",
                           "move \(WindowFixture.slackMain)"])
        #expect(fake.previews == [CGRect(x: 720, y: 25, width: 720, height: 875), CGRect(x: 0, y: 25, width: 720, height: 437.5)])

        _ = await arrange(WinPlacement(app: "chrome", region: "left-half"))
        #expect(fake.previews.count == 2)
    }

    @Test func frontmostSkipsMooring() async {
        fake.frontToBack = [ProcessInfo.processInfo.processIdentifier, WindowFixture.slack, WindowFixture.chrome]
        let result = await arranger.perform(region: "left-half", app: nil, screen: "main")
        #expect(result.results == [WinPlacementResult(app: "@frontmost", status: .ok,
                                                      frame: WinFrame(x: 0, y: 25, w: 720, h: 875))])
        #expect(frame(WindowFixture.slackMain) == CGRect(x: 0, y: 25, width: 720, height: 875))
        #expect(result.undoAvailable)

        let named = await arranger.perform(region: "right-half", app: "chrome", screen: nil)
        #expect(named.results.map(\.status) == [.ok])
    }

    @Test func listLeavesOutMooringAndNamesScreens() {
        let list = arranger.list()
        #expect(!list.apps.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
        #expect(list.apps.count == 7)
        #expect(list.screens.map(\.position) == ["main", "left"])
        #expect(list.screens[1].visibleFrame == WinFrame(x: -1920, y: -155, w: 1920, h: 1055))
        #expect(list.regions == FakeWindowSystem.regionNames)
        let slack = list.apps.first { $0.name == "Slack" }?.windows.first
        #expect(slack?.screen == 1)
        #expect(slack?.frame == WinFrame(x: -1800, y: -100, w: 1000, h: 700))
    }
}

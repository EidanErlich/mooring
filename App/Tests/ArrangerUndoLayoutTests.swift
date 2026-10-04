import CoreGraphics
import Foundation
import MooringIPC
import Testing
import WindowKit
@testable import Mooring

/// `ArrangerTests`' undo and saved-layout tests.
extension ArrangerTests {
    // MARK: Undo

    @Test func undoRestoresOnlyMovedWindows() async {
        #expect(await arranger.undo() == nil)
        let results = await arrange(WinPlacement(app: "chrome", region: "right-half", screen: "main"),
                                    WinPlacement(app: "keynote", region: "left-half"),
                                    WinPlacement(app: "slack", region: "left-half", screen: "main"))
        #expect(results.map(\.status) == [.ok, .failed, .ok])

        fake.removeWindow(WindowFixture.slackMain)
        let before = fake.calls.count
        let undone = await arranger.undo()
        #expect(undone == WinArrangeResult(results: [
            WinPlacementResult(app: "chrome", status: .ok, frame: WinFrame(x: 100, y: 100, w: 800, h: 600)),
            WinPlacementResult(app: "slack", status: .notFound, reason: "the window is gone")
        ], undoAvailable: false))
        #expect(Array(fake.calls[before...]) == ["move \(WindowFixture.chromeInbox)"])
        #expect(frame(WindowFixture.chromeInbox) == CGRect(x: 100, y: 100, width: 800, height: 600))
        #expect(await arranger.undo() == nil)
    }

    @Test func undoKeepsTen() async {
        func slackFrame(_ step: Int) -> CGRect {
            CGRect(x: Double(step) * 72, y: 25, width: 720, height: 437.5)
        }
        for step in 0..<12 {
            let frame = WinFrame(x: Double(step) / 20, y: 0, w: 0.5, h: 0.5)
            let result = await arranger.arrange(WinPlan(placements: [WinPlacement(app: "slack", frame: frame, screen: "main")]))
            #expect(result.undoAvailable)
        }
        #expect(frame(WindowFixture.slackMain)?.isClose(to: slackFrame(11)) == true)

        for step in (2..<12).reversed() {
            let undone = await arranger.undo()
            #expect(undone?.results.map(\.status) == [.ok])
            #expect(undone?.undoAvailable == (step > 2))
            #expect(frame(WindowFixture.slackMain)?.isClose(to: slackFrame(step - 1)) == true)
        }
        #expect(await arranger.undo() == nil)
        #expect(frame(WindowFixture.slackMain)?.isClose(to: slackFrame(1)) == true)
    }

    // MARK: Layouts

    @Test func layoutsSaveApplyListDelete() async throws {
        #expect(try await arranger.layout(WinLayoutArgs(action: "list")) == WinLayoutResult(names: [], arrange: nil))
        let saved = try await arranger.layout(WinLayoutArgs(action: "save", name: "coding"))
        #expect(saved == WinLayoutResult(names: ["coding"], arrange: nil))

        // Per screen, the frontmost window of each app, as fractions. Not Mooring, Finder's desktop, a minimized or
        // a full-screen window.
        let stored = try JSONDecoder().decode([String: [WinPlacement]].self, from: Data(contentsOf: layoutsURL))
        let coding = try #require(stored["coding"])
        #expect(coding.map(\.app) == ["com.google.Chrome", "com.microsoft.VSCode", "com.tinyspeck.slackmacgap",
                                      "com.apple.dt.Xcode"])
        #expect(coding.map(\.screen) == ["0", "0", "1", "1"])
        #expect(coding.allSatisfy { $0.region == nil && $0.title == nil })
        #expect(coding[2].frame == WinFrame(x: 0.0625, y: 0.0521, w: 0.5208, h: 0.6635))

        fake.setFrame(CGRect(x: 0, y: 25, width: 300, height: 300), of: WindowFixture.chromeInbox)
        fake.setFrame(CGRect(x: -1920, y: -155, width: 300, height: 300), of: WindowFixture.slackMain)
        let applied = try await arranger.layout(WinLayoutArgs(action: "apply", name: "coding"))
        #expect(applied.names == ["coding"])
        #expect(applied.arrange?.results.map(\.status) == [.ok, .ok, .ok, .ok])
        #expect(applied.arrange?.undoAvailable == true)
        let chrome = try #require(frame(WindowFixture.chromeInbox))
        let slack = try #require(frame(WindowFixture.slackMain))
        #expect(chrome.isClose(to: CGRect(x: 100, y: 100, width: 800, height: 600)))
        #expect(slack.isClose(to: CGRect(x: -1800, y: -100, width: 1000, height: 700)))

        _ = try await arranger.layout(WinLayoutArgs(action: "save", name: "b"))
        #expect(try await arranger.layout(WinLayoutArgs(action: "list")).names == ["b", "coding"])
        #expect(try await arranger.layout(WinLayoutArgs(action: "delete", name: "coding")).names == ["b"])
        let remaining = try JSONDecoder().decode([String: [WinPlacement]].self, from: Data(contentsOf: layoutsURL))
        #expect(remaining.keys.sorted() == ["b"])
    }

    @Test func layoutSaveTitlesAnAppWithWindowsOnBothScreens() async throws {
        fake.setFrame(CGRect(x: -1000, y: 0, width: 500, height: 500), of: WindowFixture.chromeDocs)
        _ = try await arranger.layout(WinLayoutArgs(action: "save", name: "split"))
        let stored = try JSONDecoder().decode([String: [WinPlacement]].self, from: Data(contentsOf: layoutsURL))
        let chrome = try #require(stored["split"]).filter { $0.app == "com.google.Chrome" }
        #expect(chrome.map(\.title) == ["Inbox – Mail – Google", "Docs – Google"])
    }

    @Test func unknownLayoutIsNotFound() async throws {
        let notFound = WireError(code: .notFound, message: "No layout named nope")
        await #expect(throws: notFound) { try await arranger.layout(WinLayoutArgs(action: "apply", name: "nope")) }
        await #expect(throws: notFound) { try await arranger.layout(WinLayoutArgs(action: "delete", name: "nope")) }
        await #expect(throws: WireError(code: .badRequest, message: "Give the layout a name")) {
            try await arranger.layout(WinLayoutArgs(action: "save", name: "  "))
        }
        await #expect(throws: WireError(code: .badRequest, message: "Unknown layout action “rename” (use save, apply, list or delete)")) {
            try await arranger.layout(WinLayoutArgs(action: "rename", name: "x"))
        }
        #expect(fake.calls.isEmpty)
    }
}

extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

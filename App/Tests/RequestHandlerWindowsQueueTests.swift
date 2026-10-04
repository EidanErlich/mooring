import CoreGraphics
import Foundation
import MooringIPC
import Testing
@testable import Mooring

/// `RequestHandlerWindowsTests` continued: layouts, undo, arrangements side by side, and the notification.
extension RequestHandlerWindowsTests {
    @Test func layoutApplyAsks() async throws {
        mode(.askFirst)
        // Saving, listing and deleting don't ask.
        #expect(await send(.winLayout(WinLayoutArgs(action: "save", name: "coding"))).ok)
        #expect(await send(.winLayout(WinLayoutArgs(action: "save", name: "spare"))).ok)
        #expect(await send(.winLayout(WinLayoutArgs(action: "delete", name: "spare"))).ok)
        #expect(approver.calls.isEmpty)
        let moved = CGRect(x: 0, y: 25, width: 300, height: 300)
        fake.setFrame(moved, of: WindowFixture.chromeInbox)

        approver.answers = [.deny]
        let refused = await send(.winLayout(WinLayoutArgs(action: "apply", name: "coding")))
        #expect(wireFailure(refused) == denied("Window arrangement not approved (denied)"))
        #expect(frame(WindowFixture.chromeInbox) == moved)

        approver.answers = [.allow]
        let applied = await send(.winLayout(WinLayoutArgs(action: "apply", name: "coding")))
        #expect(results(applied)?.isEmpty == false)
        #expect(results(applied)?.allSatisfy { $0.status == .ok } == true)
        let restored = try #require(frame(WindowFixture.chromeInbox))
        #expect(abs(restored.minX - 100) < 1 && abs(restored.width - 800) < 1)
        #expect(approver.calls.count == 2)
        let call = try #require(approver.calls.last)
        #expect(call.title == "Claude Code wants to arrange \(results(applied)?.count ?? 0) windows")
        #expect(call.body.hasPrefix("Layout “coding”: com.google.Chrome → "))

        // A layout that doesn't exist is reported without asking.
        let missing = await send(.winLayout(WinLayoutArgs(action: "apply", name: "nope")))
        #expect(wireFailure(missing) == WireError(code: .notFound, message: "No layout named nope"))
        #expect(approver.calls.count == 2)
    }

    /// What moves is the layout the person approved, even if it's saved over while they decide.
    @Test func layoutAppliesApprovedPlacements() async throws {
        let suite = Self(center: .seconds(10))
        suite.mode(.askFirst)
        #expect(await suite.send(.winLayout(WinLayoutArgs(action: "save", name: "coding"))).ok)
        let moved = CGRect(x: 0, y: 25, width: 300, height: 300)
        suite.fake.setFrame(moved, of: WindowFixture.chromeInbox)

        let reply = Task { await suite.send(.winLayout(WinLayoutArgs(action: "apply", name: "coding"))) }
        let post = try #require(await suite.post(titled: "Claude Code wants to arrange 4 windows"))
        #expect(post.body.contains("com.google.Chrome → 56% × 69% at 7%, 9%"))
        // Saved over (capturing Chrome where it is now) before the person answers.
        #expect(await suite.send(.winLayout(WinLayoutArgs(action: "save", name: "coding")), from: Self.person).ok)
        suite.fixture.windowCenter?.handle(actionIdentifier: WindowApprovalCenter.allowAction, requestID: post.id)

        let applied = await reply.value
        #expect(suite.results(applied)?.count == 4)
        let chrome = try #require(suite.frame(WindowFixture.chromeInbox))
        #expect(abs(chrome.minX - 100) < 1 && abs(chrome.width - 800) < 1)
    }

    @Test func undoDoesNotAsk() async {
        mode(.askFirst)
        approver.answers = [.allow]
        _ = await arrange(Self.chromeRight)
        #expect(approver.calls.count == 1)

        let undone = await send(.winUndo(WinUndoArgs()))
        #expect(results(undone)?.map(\.status) == [.ok])
        #expect(frame(WindowFixture.chromeInbox) == CGRect(x: 100, y: 100, width: 800, height: 600))
        #expect(approver.calls.count == 1)

        let nothing = await send(.winUndo(WinUndoArgs()))
        #expect(wireFailure(nothing) == WireError(code: .notFound, message: "Nothing to undo"))
    }

    /// Two agents at once: each gets its own notification and answer, and each arrangement is its own undo.
    @Test func concurrentAsksAreIndependent() async throws {
        let suite = Self(center: .seconds(10))
        suite.mode(.askFirst)
        let center = try #require(suite.fixture.windowCenter)
        let first = Task { await suite.arrange(Self.chromeRight, from: Self.claude) }
        let second = Task { await suite.arrange(Self.slackLeft, from: Self.codex) }
        let claudePost = try #require(await suite.post(titled: "Claude Code wants to arrange 1 window"))
        let codexPost = try #require(await suite.post(titled: "Codex wants to arrange 1 window"))
        #expect(suite.poster.posts.count == 2)
        #expect(claudePost.id != codexPost.id)
        #expect(claudePost.body == "chrome → right half")
        #expect(codexPost.body == "slack → left half")

        // Codex is answered first and moves while Claude's ask still waits.
        center.handle(actionIdentifier: WindowApprovalCenter.allowAction, requestID: codexPost.id)
        #expect(suite.results(await second.value)?.map(\.status) == [.ok])
        #expect(suite.frame(WindowFixture.slackMain) == CGRect(x: -1920, y: -155, width: 960, height: 1055))
        #expect(suite.frame(WindowFixture.chromeInbox) == CGRect(x: 100, y: 100, width: 800, height: 600))

        center.handle(actionIdentifier: WindowApprovalCenter.allowAction, requestID: claudePost.id)
        #expect(suite.results(await first.value)?.map(\.status) == [.ok])
        #expect(suite.frame(WindowFixture.chromeInbox) == CGRect(x: 720, y: 25, width: 720, height: 875))

        // Each arrangement undoes on its own, latest first.
        #expect(await suite.send(.winUndo(WinUndoArgs()), from: Self.claude).ok)
        #expect(suite.frame(WindowFixture.chromeInbox) == CGRect(x: 100, y: 100, width: 800, height: 600))
        #expect(suite.frame(WindowFixture.slackMain) == CGRect(x: -1920, y: -155, width: 960, height: 1055))
        #expect(await suite.send(.winUndo(WinUndoArgs()), from: Self.codex).ok)
        #expect(suite.frame(WindowFixture.slackMain) == CGRect(x: -1800, y: -100, width: 1000, height: 700))
    }

    /// Arrangements never overlap: a second one waits until the first has applied.
    @Test func arrangementsApplyOneAtATime() async {
        let lock = SerialLock()
        let log = OrderLog()
        let first = Task { @MainActor in
            await lock.run {
                log.order.append("first start")
                try? await Task.sleep(for: .milliseconds(50))
                log.order.append("first end")
            }
        }
        await Task.yield()
        let second = Task { @MainActor in
            await lock.run { log.order.append("second") }
        }
        await first.value
        await second.value
        #expect(log.order == ["first start", "first end", "second"])
    }

    // MARK: - The notification

    @Test func notificationTitleAndBody() async throws {
        let suite = Self(center: .seconds(10))
        suite.mode(.askFirst)
        let reply = Task { await suite.arrange(Self.chromeRight, Self.itermBottomLeft) }
        let post = try #require(await suite.post(titled: "Claude Code wants to arrange 2 windows"))
        #expect(post.body == "chrome → right half · iterm → bottom left")
        #expect(post.category == "mooring.window-approval")
        #expect(post.id.hasPrefix("win-"))
        suite.fixture.windowCenter?.handle(actionIdentifier: "mooring.deny-arrange", requestID: post.id)
        #expect(wireFailure(await reply.value) == denied("Window arrangement not approved (denied)"))

        let category = WindowApprovalCenter.category
        #expect(category.identifier == "mooring.window-approval")
        #expect(category.actions.map(\.identifier) == ["mooring.allow-arrange", "mooring.deny-arrange"])
        #expect(category.actions.map(\.title) == ["Allow", "Deny"])
        #expect(category.actions[1].options.contains(.destructive))
        #expect(category.actions.allSatisfy { !$0.options.contains(.foreground) })

        #expect(WindowApproval.title(agent: "Codex", count: 1) == "Codex wants to arrange 1 window")
        #expect(WindowApproval.body([
            WinPlacement(app: WinPlacement.frontmostApp, region: "maximize"),
            WinPlacement(app: "chrome", region: "left-half", screen: "right", title: "Docs"),
            WinPlacement(app: "slack", frame: WinFrame(x: 0.5, y: 0, w: 0.5, h: 1), screen: "1")
        ]) == "the frontmost app → maximize · chrome “Docs” → left half on the right screen · "
            + "slack → 50% × 100% at 50%, 0% on screen 1")
        let many = (1...9).map { WinPlacement(app: "app\($0)", region: "center") }
        #expect(WindowApproval.body(many).hasSuffix("app6 → center · and 3 more"))
    }
}

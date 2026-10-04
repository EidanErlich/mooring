import AwakeKit
import CoreGraphics
import Foundation
import MooringIPC
import Testing
import WindowKit
@testable import Mooring

/// Answers window asks from a script: `.timeout` once the answers run out.
@MainActor
final class FakeWindowApprover: WindowApproving {
    struct Call: Equatable {
        let title: String
        let body: String
    }

    var answers: [WindowAnswer] = []
    private(set) var calls: [Call] = []

    func ask(title: String, body: String) async -> WindowAnswer {
        calls.append(Call(title: title, body: body))
        return answers.isEmpty ? .timeout : answers.removeFirst()
    }
}

@MainActor
private final class OrderLog {
    var order: [String] = []
}

/// `win.*` through the handler: Windows must be on, then the agent mode decides, then an ask may run.
@MainActor
struct RequestHandlerWindowsTests {
    let fixture: RequestFixture
    let fake = WindowFixture.system()
    let poster = FakeNotificationPoster()

    static let chromeRight = WinPlacement(app: "chrome", region: "right-half")
    static let itermBottomLeft = WinPlacement(app: "iterm", region: "bottom-left")
    static let slackLeft = WinPlacement(app: "slack", region: "left-half")
    static let claude = Caller(uid: 501, pid: 200, identity: .agent("Claude Code"))
    static let codex = Caller(uid: 501, pid: 300, identity: .agent("Codex"))
    static let person = Caller(uid: 501, pid: 77)

    init() {
        self.init(center: nil)
    }

    /// The fixture's caller (pid 200) runs under `claude`, so it counts as Claude Code; pid 77 is a person. With a
    /// `center` timeout, a real `WindowApprovalCenter` over `poster` answers the asks instead of the scripted approver.
    init(center timeout: Duration?) {
        let center = timeout.map { [poster] in WindowApprovalCenter(poster: poster, timeout: $0) }
        fixture = RequestFixture(table: FakeProcessTable([(200, "sh"), (100, "claude")]), callerPID: 200,
                                 windowCenter: center)
        fixture.knobs.windowsState = .on
        let layoutsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RequestHandlerWindowsTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("layouts.json")
        fixture.knobs.arranger = Arranger(system: fake, layoutsURL: layoutsURL, locateApp: { _ in nil },
                                          launchTimeout: .milliseconds(100), pollInterval: .milliseconds(10))
    }

    var approver: FakeWindowApprover { fixture.windowApprover }

    func mode(_ mode: AgentWindowMode) {
        fixture.knobs.settings.agentWindows = mode
    }

    func arrange(_ placements: WinPlacement..., from caller: Caller? = nil) async -> Response {
        await send(.winArrange(WinPlan(placements: placements)), from: caller)
    }

    func send(_ args: RequestArgs, from caller: Caller? = nil) async -> Response {
        guard let caller else { return await fixture.send(args) }
        let operation: Op = switch args {
        case .winList: .winList
        case .winUndo: .winUndo
        case .winLayout: .winLayout
        default: .winArrange
        }
        return await fixture.handler.handle(Request(v: 1, id: "r1", op: operation, args: args), from: caller)
    }

    func results(_ response: Response) -> [WinPlacementResult]? {
        switch response.result {
        case .winArrange(let result)?, .winUndo(let result)?: result.results
        case .winLayout(let result)?: result.arrange?.results
        default: nil
        }
    }

    func frame(_ id: CGWindowID) -> CGRect? {
        fake.window(id)?.frame
    }

    /// The window-approval post titled `title`, once it's been posted.
    func post(titled title: String) async -> FakeNotificationPoster.Post? {
        for _ in 0..<2000 where !poster.posts.contains(where: { $0.title == title }) {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return poster.posts.first { $0.title == title }
    }

    // MARK: - Windows on

    @Test func windowsOffDeniesEveryOp() async {
        let off = denied("Windows is off. Turn it on in Mooring (Windows › Turn On…).")
        let ops: [RequestArgs] = [
            .winList, .winArrange(WinPlan(placements: [Self.chromeRight])), .winUndo,
            .winLayout(WinLayoutArgs(action: "list")), .winLayout(WinLayoutArgs(action: "save", name: "coding")),
            .winLayout(WinLayoutArgs(action: "apply", name: "coding"))
        ]
        for state in [WindowsController.State.off, .waitingForTrust, .needsAccessibility] {
            fixture.knobs.windowsState = state
            for agentMode in [AgentWindowMode.automatic, .askFirst, .off] {
                mode(agentMode)
                for args in ops {
                    #expect(wireFailure(await send(args)) == off)
                    #expect(wireFailure(await send(args, from: Self.person)) == off)
                }
            }
        }
        #expect(fake.calls.isEmpty)
        #expect(approver.calls.isEmpty)
    }

    // MARK: - Agent mode

    @Test func agentOffDenies() async {
        mode(.off)
        let off = denied("Window arrangement by agents is off in Settings")
        #expect(wireFailure(await arrange(Self.chromeRight)) == off)
        #expect(wireFailure(await send(.winUndo)) == off)
        #expect(wireFailure(await send(.winLayout(WinLayoutArgs(action: "save", name: "coding")))) == off)
        #expect(wireFailure(await send(.winLayout(WinLayoutArgs(action: "apply", name: "coding")))) == off)
        #expect(wireFailure(await send(.winLayout(WinLayoutArgs(action: "delete", name: "coding")))) == off)
        // An MCP client is an agent too, whatever its ancestry.
        let mcp = WinPlan(placements: [Self.chromeRight], client: "claude-ai")
        #expect(wireFailure(await send(.winArrange(mcp), from: Self.person)) == off)
        #expect(fake.calls.isEmpty)
        #expect(approver.calls.isEmpty)
        // Reading is still allowed.
        #expect(await send(.winList).ok)
        #expect(await send(.winLayout(WinLayoutArgs(action: "list"))).ok)
    }

    @Test func personNeverAsked() async {
        for agentMode in [AgentWindowMode.askFirst, .off] {
            mode(agentMode)
            let detected = await arrange(Self.chromeRight, from: Self.person)
            #expect(results(detected)?.map(\.status) == [.ok])
            #expect(frame(WindowFixture.chromeInbox) == CGRect(x: 720, y: 25, width: 720, height: 875))
            // Shortcuts and links name the person outright, whatever the ancestry.
            let named = await arrange(Self.slackLeft, from: Caller(uid: 501, pid: 200, identity: .person))
            #expect(results(named)?.map(\.status) == [.ok])
            #expect(await send(.winUndo, from: Self.person).ok)
        }
        #expect(approver.calls.isEmpty)
    }

    @Test func automaticAgentIsNotAsked() async {
        let response = await arrange(Self.chromeRight)
        #expect(results(response)?.map(\.status) == [.ok])
        #expect(approver.calls.isEmpty)
    }

    // MARK: - Ask first

    @Test func askFirstAllowApplies() async {
        mode(.askFirst)
        approver.answers = [.allow]
        let response = await arrange(Self.chromeRight, Self.itermBottomLeft)
        #expect(results(response)?.map(\.status) == [.ok, .ok])
        #expect(frame(WindowFixture.chromeInbox) == CGRect(x: 720, y: 25, width: 720, height: 875))
        #expect(approver.calls == [FakeWindowApprover.Call(
            title: "Claude Code wants to arrange 2 windows", body: "chrome → right half · iterm → bottom left"
        )])
    }

    @Test func askFirstDenyDenies() async {
        mode(.askFirst)
        approver.answers = [.deny]
        let response = await arrange(Self.chromeRight)
        #expect(wireFailure(response) == denied("Window arrangement not approved (denied)"))
        #expect(fake.calls.isEmpty)
        #expect(approver.calls.count == 1)
    }

    @Test func askFirstTimeoutDenies() async {
        let suite = Self(center: .milliseconds(50))
        suite.mode(.askFirst)
        let response = await suite.arrange(Self.chromeRight)
        #expect(wireFailure(response) == denied("Window arrangement not approved (no answer in 60 s)"))
        #expect(suite.fake.calls.isEmpty)
        #expect(suite.poster.posts.count == 1)
        #expect(suite.poster.withdrawn == suite.poster.posts.map(\.id))
    }

    @Test func askFirstWithoutNotificationsDenies() async {
        let suite = Self(center: .seconds(10))
        suite.mode(.askFirst)
        suite.poster.authorized = false
        let response = await suite.arrange(Self.chromeRight)
        #expect(wireFailure(response)
            == denied("Turn on notifications for Mooring in System Settings to approve window arrangement"))
        #expect(suite.fake.calls.isEmpty)
    }

    /// Windows turned off while the person was deciding: the Allow moves nothing.
    @Test func windowsTurnedOffDuringAskMovesNothing() async throws {
        let suite = Self(center: .seconds(10))
        suite.mode(.askFirst)
        let reply = Task { await suite.arrange(Self.chromeRight) }
        let post = try #require(await suite.post(titled: "Claude Code wants to arrange 1 window"))
        suite.fixture.knobs.windowsState = .off
        suite.fixture.windowCenter?.handle(actionIdentifier: WindowApprovalCenter.allowAction, requestID: post.id)
        #expect(wireFailure(await reply.value) == denied("Windows is off. Turn it on in Mooring (Windows › Turn On…)."))
        #expect(suite.fake.calls.isEmpty)
    }

    @Test func listNeverAsks() async {
        mode(.askFirst)
        let response = await send(.winList)
        guard case .winList(let list)? = response.result else {
            Issue.record("expected a list, got \(response)")
            return
        }
        #expect(list.apps.contains { $0.name == "Google Chrome" })
        #expect(!list.apps.contains { $0.name == "Mooring" })
        #expect(await send(.winLayout(WinLayoutArgs(action: "list"))).ok)
        #expect(approver.calls.isEmpty)
        #expect(fake.calls.isEmpty)
    }

    @Test func badPlanIsRefusedWithoutAsking() async {
        mode(.askFirst)
        let response = await send(.winArrange(WinPlan(placements: [])))
        #expect(wireFailure(response) == WireError(code: .badRequest, message: "A plan needs at least one placement"))
        #expect(approver.calls.isEmpty)
    }

}

// MARK: - Layouts, undo, concurrency and the notification

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

    @Test func undoDoesNotAsk() async {
        mode(.askFirst)
        approver.answers = [.allow]
        _ = await arrange(Self.chromeRight)
        #expect(approver.calls.count == 1)

        let undone = await send(.winUndo)
        #expect(results(undone)?.map(\.status) == [.ok])
        #expect(frame(WindowFixture.chromeInbox) == CGRect(x: 100, y: 100, width: 800, height: 600))
        #expect(approver.calls.count == 1)

        let nothing = await send(.winUndo)
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
        #expect(await suite.send(.winUndo, from: Self.claude).ok)
        #expect(suite.frame(WindowFixture.chromeInbox) == CGRect(x: 100, y: 100, width: 800, height: 600))
        #expect(suite.frame(WindowFixture.slackMain) == CGRect(x: -1920, y: -155, width: 960, height: 1055))
        #expect(await suite.send(.winUndo, from: Self.codex).ok)
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

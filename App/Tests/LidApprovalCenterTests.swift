import Foundation
import Testing
import UserNotifications
@testable import Mooring

/// Records what would have been posted; never touches the real notification center.
@MainActor
final class FakeNotificationPoster: NotificationPosting {
    struct Post: Equatable {
        let id: String
        let title: String
        let body: String
        let userInfo: [String: String]
        let category: String?
    }

    var authorized = true
    /// What `post` reports: false when the system refused the notification.
    var postSucceeds = true
    var status: String? = "allowed"
    var posts: [Post] = []
    var withdrawn: [String] = []
    /// Ids of the approvals Notification Center still shows.
    var delivered: [String] = []
    var authorizeCalls = 0

    func authorize() async -> Bool {
        authorizeCalls += 1
        return authorized
    }

    func notificationStatus() async -> String? { status }

    func post(id: String, title: String, body: String, userInfo: [String: String], category: String?) async -> Bool {
        posts.append(Post(id: id, title: title, body: body, userInfo: userInfo, category: category))
        return postSucceeds
    }

    func withdraw(id: String) {
        withdrawn.append(id)
    }

    func deliveredApprovalIDs(category: String) async -> [String] { delivered }

    /// Waits until `count` notifications have been posted (or about 2 s pass).
    func waitForPosts(_ count: Int) async {
        for _ in 0..<2000 where posts.count < count {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

@MainActor
struct LidApprovalCenterTests {
    private let poster = FakeNotificationPoster()

    private func answer(_ action: String, timeout: Duration = .seconds(10)) async -> LidAnswer {
        let center = LidApprovalCenter(poster: poster, timeout: timeout)
        let ask = Task { await center.ask(leaseID: "anchor-1", agent: "Claude Code", body: "tests · with no end time") }
        await poster.waitForPosts(1)
        center.handle(actionIdentifier: action, requestID: poster.posts[0].id)
        return await ask.value
    }

    @Test func actionsMapToAnswers() {
        #expect(LidApprovalCenter.answer(forAction: "mooring.allow-once") == .allowOnce)
        #expect(LidApprovalCenter.answer(forAction: "mooring.always-allow") == .alwaysAllow)
        #expect(LidApprovalCenter.answer(forAction: "mooring.deny") == .deny)
        #expect(LidApprovalCenter.answer(forAction: "com.apple.UNNotificationDefaultActionIdentifier") == nil)
        #expect(LidApprovalCenter.answer(forAction: "com.apple.UNNotificationDismissActionIdentifier") == nil)
        let category = LidApprovalCenter.category
        #expect(category.identifier == "mooring.lid-approval")
        #expect(category.actions.map(\.identifier) == ["mooring.allow-once", "mooring.always-allow", "mooring.deny"])
        #expect(category.actions.map(\.title) == ["Allow once", "Always allow this agent", "Deny"])
        #expect(category.actions[2].options.contains(.destructive))
        #expect(category.actions.allSatisfy { !$0.options.contains(.foreground) })
    }

    @Test func allowOnceResolvesTheAsk() async {
        #expect(await answer("mooring.allow-once") == .allowOnce)
        let post = poster.posts[0]
        #expect(post.id.hasPrefix("lid-anchor-1-"))
        #expect(post.userInfo == ["leaseID": "anchor-1"])
        #expect(post.category == LidApprovalCenter.categoryID)
        #expect(post.title == "Claude Code wants to keep your Mac awake with the lid closed")
        #expect(post.body == "Claude Code · tests · with no end time")
    }

    @Test func alwaysAllowResolvesTheAsk() async {
        #expect(await answer("mooring.always-allow") == .alwaysAllow)
    }

    @Test func denyResolvesTheAsk() async {
        #expect(await answer("mooring.deny") == .deny)
    }

    @Test func timeoutResolvesAfterTheLimit() async {
        let center = LidApprovalCenter(poster: poster, timeout: .milliseconds(100))
        let start = ContinuousClock.now
        let answer = await center.ask(leaseID: "anchor-1", agent: "Claude Code", body: "tests")
        let elapsed = ContinuousClock.now - start
        #expect(answer == .timeout)
        #expect(elapsed >= .milliseconds(100) && elapsed < .seconds(2))
        #expect(center.pending.isEmpty)
        #expect(poster.withdrawn == [poster.posts[0].id])
    }

    @Test func unauthorizedIsUnavailableImmediately() async {
        poster.authorized = false
        let center = LidApprovalCenter(poster: poster, timeout: .seconds(10))
        let start = ContinuousClock.now
        #expect(await center.ask(leaseID: "anchor-1", agent: "Claude Code", body: "tests") == .unavailable)
        #expect(ContinuousClock.now - start < .seconds(1))
        #expect(poster.posts.isEmpty)
        #expect(center.pending.isEmpty)
    }

    @Test func failedPostAnswersUnavailableAtOnce() async {
        poster.postSucceeds = false
        let center = LidApprovalCenter(poster: poster, timeout: .seconds(60))
        let start = ContinuousClock.now
        #expect(await center.ask(leaseID: "anchor-1", agent: "Claude Code", body: "tests") == .unavailable)
        #expect(ContinuousClock.now - start < .seconds(1))
        #expect(center.pending.isEmpty)
    }

    @Test func failedWindowPostAnswersUnavailableAtOnce() async {
        poster.postSucceeds = false
        let center = WindowApprovalCenter(poster: poster, timeout: .seconds(60))
        let start = ContinuousClock.now
        #expect(await center.ask(title: "Claude Code wants to arrange windows", body: "tidy") == .unavailable)
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func pendingTracksTheLeaseUntilResolved() async {
        let center = LidApprovalCenter(poster: poster, timeout: .seconds(10))
        #expect(center.pending.isEmpty)
        let ask = Task { await center.ask(leaseID: "anchor-1", agent: "Claude Code", body: "tests") }
        await poster.waitForPosts(1)
        #expect(center.pending == ["anchor-1"])
        // The body tap and dismissal don't answer, so the lease stays pending.
        center.handle(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier", requestID: poster.posts[0].id)
        center.handle(actionIdentifier: "mooring.allow-once", requestID: "lid-anchor-1-unknown")
        #expect(center.pending == ["anchor-1"])
        center.handle(actionIdentifier: "mooring.deny", requestID: poster.posts[0].id)
        #expect(await ask.value == .deny)
        #expect(center.pending.isEmpty)
    }

    @Test func lateResponseAfterTimeoutIsIgnored() async {
        let center = LidApprovalCenter(poster: poster, timeout: .milliseconds(100))
        #expect(await center.ask(leaseID: "anchor-1", agent: "Claude Code", body: "tests") == .timeout)
        center.handle(actionIdentifier: "mooring.allow-once", requestID: poster.posts[0].id)
        #expect(center.pending.isEmpty)
        // A fresh ask isn't answered by the stale response either.
        let next = Task { await center.ask(leaseID: "anchor-1", agent: "Claude Code", body: "tests") }
        await poster.waitForPosts(2)
        center.handle(actionIdentifier: "mooring.allow-once", requestID: poster.posts[0].id)
        #expect(center.pending == ["anchor-1"])
        center.handle(actionIdentifier: "mooring.deny", requestID: poster.posts[1].id)
        #expect(await next.value == .deny)
    }

    @Test func concurrentAsksResolveIndependently() async {
        let center = LidApprovalCenter(poster: poster, timeout: .seconds(10))
        let first = Task { await center.ask(leaseID: "anchor-1", agent: "Claude Code", body: "tests") }
        await poster.waitForPosts(1)
        let second = Task { await center.ask(leaseID: "anchor-2", agent: "Codex", body: "build") }
        await poster.waitForPosts(2)
        #expect(poster.posts.count == 2 && poster.posts[0].id != poster.posts[1].id)
        #expect(center.pending == ["anchor-1", "anchor-2"])
        center.handle(actionIdentifier: "mooring.always-allow", requestID: poster.posts[1].id)
        #expect(await second.value == .alwaysAllow)
        #expect(center.pending == ["anchor-1"])
        center.handle(actionIdentifier: "mooring.deny", requestID: poster.posts[0].id)
        #expect(await first.value == .deny)
        #expect(center.pending.isEmpty)
    }

    @Test func staleApprovalsAreRemovedAtLaunch() async {
        let center = LidApprovalCenter(poster: poster, timeout: .seconds(10))
        let ask = Task { await center.ask(leaseID: "anchor-1", agent: "Claude Code", body: "tests") }
        await poster.waitForPosts(1)
        let live = poster.posts[0].id
        poster.delivered = ["lid-anchor-9-from-before", live]

        await center.removeStaleApprovals()

        // Only the one no ask is waiting for: its buttons would do nothing.
        #expect(poster.withdrawn == ["lid-anchor-9-from-before"])
        center.handle(actionIdentifier: LidApprovalCenter.denyAction, requestID: live)
        #expect(await ask.value == .deny)
    }
}

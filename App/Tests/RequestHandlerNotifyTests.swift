import AwakeKit
import Foundation
import MooringIPC
import Testing
@testable import Mooring

extension RequestFixture {
    func notify(_ title: String, _ body: String? = nil, client: String? = nil) async -> Response {
        await send(.notify(NotifyArgs(title: title, body: body, client: client)))
    }
}

/// The `notify` op: who may post, how often, and what the notification says (stage 2c-2).
@MainActor
struct RequestHandlerNotifyTests {
    private func posted(_ response: Response) -> Bool? {
        if case .notify(let result)? = response.result { result.posted } else { nil }
    }

    @Test func agentNotifyPostsWithPrefix() async throws {
        let fixture = RequestFixture.agent()

        let response = await fixture.notify("Done", "Refactor finished")

        #expect(posted(response) == true)
        let post = try #require(fixture.poster.posts.first)
        #expect(post.title == "Claude Code: Done")
        #expect(post.body == "Refactor finished")
        #expect(post.category == nil)
        #expect(post.id.hasPrefix("notify-"))
    }

    @Test func notifyReportsAFailedPost() async {
        let fixture = RequestFixture.agent()
        fixture.poster.postSucceeds = false

        #expect(posted(await fixture.notify("Done")) == false)
        #expect(fixture.poster.posts.count == 1)
    }

    @Test func personNotifyIsTitledTerminal() async throws {
        let fixture = RequestFixture()

        #expect(posted(await fixture.notify("Backup done")) == true)

        #expect(try #require(fixture.poster.posts.first).title == "Terminal: Backup done")
    }

    @Test func mcpNotifyIsTitledByClient() async throws {
        let fixture = RequestFixture()

        #expect(posted(await fixture.notify("Done", client: "claude-ai")) == true)

        #expect(try #require(fixture.poster.posts.first).title == "Claude Desktop: Done")
    }

    @Test func clientNamedTerminalBecomesMCPClient() async throws {
        let fixture = RequestFixture()

        #expect(posted(await fixture.notify("Done", client: " terminal\n")) == true)

        #expect(try #require(fixture.poster.posts.first).title.hasPrefix("MCP client: "))
    }

    @Test func rotatingClientNamesShareThePidLimit() async {
        let fixture = RequestFixture()
        #expect(posted(await fixture.notify("One", client: "a")) == true)

        fixture.knobs.clock += 5
        #expect(wireFailure(await fixture.notify("Two", client: "b")) == denied("Rate-limited: try again in 25 s"))

        #expect(fixture.poster.posts.count == 1)
    }

    @Test func agentNotifyIsRateLimited() async {
        let fixture = RequestFixture.agent()
        #expect(posted(await fixture.notify("One")) == true)

        fixture.knobs.clock += 10
        #expect(wireFailure(await fixture.notify("Two")) == denied("Rate-limited: try again in 20 s"))

        fixture.knobs.clock += 20
        #expect(posted(await fixture.notify("Three")) == true)
        #expect(fixture.poster.posts.map(\.title) == ["Claude Code: One", "Claude Code: Three"])
    }

    @Test func clockMovedBackDoesNotBlockNotify() async {
        let fixture = RequestFixture.agent()
        #expect(posted(await fixture.notify("One")) == true)

        fixture.knobs.clock -= 3600
        #expect(posted(await fixture.notify("Two")) == true)

        fixture.knobs.clock += 5
        #expect(wireFailure(await fixture.notify("Three")) == denied("Rate-limited: try again in 25 s"))
    }

    @Test func personNotifyIsNotRateLimited() async {
        let fixture = RequestFixture()

        #expect(posted(await fixture.notify("One")) == true)
        #expect(posted(await fixture.notify("Two")) == true)

        #expect(fixture.poster.posts.count == 2)
    }

    @Test func agentNotifyOffInSettings() async {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentNotifications = false

        let response = await fixture.notify("Done")

        #expect(wireFailure(response) == denied("Notifications from agents are turned off in Settings"))
        #expect(fixture.poster.posts.isEmpty)
    }

    @Test func notifyWithoutPermission() async {
        let fixture = RequestFixture()
        fixture.poster.authorized = false

        let response = await fixture.notify("Done")

        #expect(wireFailure(response) == denied("Turn on notifications for Mooring in System Settings"))
        #expect(fixture.poster.posts.isEmpty)
    }

    @Test func notifyCleansAndTruncates() async throws {
        let fixture = RequestFixture.agent()
        let title = "Line one\n" + String(repeating: "t", count: 191)

        _ = await fixture.notify(title, String(repeating: "b", count: 500))

        let post = try #require(fixture.poster.posts.first)
        let prefix = "Claude Code: "
        #expect(post.title.hasPrefix(prefix))
        let own = post.title.dropFirst(prefix.count)
        #expect(own.count <= 80)
        #expect(!own.contains("\n"))
        #expect(post.body.count == 300)
    }
}

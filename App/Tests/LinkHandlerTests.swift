import AwakeKit
import Foundation
import MooringIPC
import Testing
@testable import Mooring

/// `mooring://` links carried out through the request handler (stage 2c-2).
@MainActor
struct LinkHandlerTests {
    private let fixture = RequestFixture()
    private let poster = FakeNotificationPoster()

    /// A link handler over the fixture's handler, naming every sender `name`.
    private func links(appName name: String? = "Raycast") -> LinkHandler {
        let gate = HandlerGate()
        gate.set(fixture.handler)
        let knobs = fixture.knobs
        return LinkHandler(gate: gate, poster: poster, appName: { _ in name }, now: { knobs.clock })
    }

    private func open(_ links: LinkHandler, _ text: String, senderPID: Int32? = 4242) async throws {
        await links.open(try #require(URL(string: text)), senderPID: senderPID)
    }

    @Test func senderNameBecomesAgent() async throws {
        try await open(links(), "mooring://on?level=lid")

        #expect(fixture.approver.calls.map(\.agent) == ["Raycast"])
        #expect(fixture.approver.calls.map(\.leaseID) == [AwakeEngine.menuLeaseID])
    }

    @Test func noSenderIsALink() async throws {
        try await open(links(appName: "Mooring"), "mooring://on?level=lid", senderPID: nil)

        #expect(fixture.approver.calls.map(\.agent) == ["A link"])
    }

    @Test func boundedLidNeedsNoPrompt() async throws {
        try await open(links(), "mooring://on?for=2h&level=lid")

        #expect(fixture.approver.calls.isEmpty)
        let lease = try #require(fixture.lease(AwakeEngine.menuLeaseID))
        #expect(lease.level == lidOnly)
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(7200))
        #expect(poster.posts.isEmpty)
    }

    @Test func neverPostsErrorAndStillTurnsOn() async throws {
        fixture.knobs.settings.agentLidApproval = .never

        try await open(links(), "mooring://on?level=lid")

        let lease = try #require(fixture.lease(AwakeEngine.menuLeaseID))
        #expect(!lease.level.lid)
        #expect(poster.posts.count == 1)
        let post = try #require(poster.posts.first)
        #expect(post.title == "Mooring couldn't use that link")
        #expect(post.body == LidMessage.never)
        #expect(post.category == nil)
        #expect(post.id.hasPrefix("link-error-"))
    }

    @Test func parseErrorPostsOnce() async throws {
        let links = links()

        try await open(links, "mooring://onn")
        fixture.knobs.clock += LinkHandler.errorInterval - 1
        try await open(links, "mooring://on?level=lidd")

        #expect(poster.posts.map(\.body) == ["unknown action 'onn'"])

        fixture.knobs.clock += 1
        try await open(links, "mooring://on?for=soon")

        #expect(poster.posts.map(\.body) == ["unknown action 'onn'", "'for' must look like 30m or 1h30m"])
    }

    @Test func toggleTurnsOffWhenOn() async throws {
        let links = links()
        try await open(links, "mooring://on")
        #expect(fixture.engine.hasMenuSession)

        try await open(links, "mooring://toggle?for=1h")

        #expect(!fixture.engine.hasMenuSession)
        #expect(poster.posts.isEmpty)
    }

    @Test func toggleTurnsOnWhenOff() async throws {
        try await open(links(), "mooring://toggle?for=1h&level=display")

        let lease = try #require(fixture.lease(AwakeEngine.menuLeaseID))
        #expect(lease.level == AwakeLevel(display: true, lid: false))
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(3600))
        #expect(poster.posts.isEmpty)
    }
}

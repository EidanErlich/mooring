import AwakeKit
import Foundation
import MooringIPC
import Testing
@testable import Mooring

/// Acquiring a named lease again merges with it and never weakens it.
@MainActor
struct RequestHandlerReacquireTests {
    @Test func reacquireKeepsTheWatch() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", watchPid: 4242)
        let response = await fixture.acquire(.lease, id: "job", ttl: 600)
        #expect(response.ok)
        #expect(try #require(fixture.lease("job")).watch?.pid == 4242)
        #expect(acquireResult(response)?.lease.watchPid == 4242)
    }

    @Test func reacquireWithANewWatchReplacesTheWatch() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", watchPid: 4242)
        _ = await fixture.acquire(.lease, id: "job", watchPid: 4343)
        #expect(try #require(fixture.lease("job")).watch?.pid == 4343)
    }

    @Test func reacquireNeverShortens() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 3600)
        let first = fixture.clock.addingTimeInterval(3600)
        fixture.knobs.clock = fixture.clock.addingTimeInterval(100)

        let response = await fixture.acquire(.lease, id: "job", ttl: 600)
        #expect(response.ok)
        let lease = try #require(fixture.lease("job"))
        let expiry = try #require(lease.expiresAt)
        #expect(abs(expiry.timeIntervalSince(first)) < 0.001)
        #expect(acquireResult(response)?.clamped == false)
    }

    @Test func reacquireKeepsTheLongerTTL() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 3600)
        fixture.knobs.clock = fixture.clock.addingTimeInterval(1800)

        _ = await fixture.acquire(.lease, id: "job", ttl: 60)
        let lease = try #require(fixture.lease("job"))
        #expect(lease.ttl == 3600)
        #expect(try #require(lease.expiresAt) == fixture.clock.addingTimeInterval(1800))

        _ = await fixture.renew("job")
        #expect(try #require(fixture.lease("job")).expiresAt == fixture.clock.addingTimeInterval(3600))
    }

    @Test func reacquireExtendsWhenLonger() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 600)
        fixture.knobs.clock = fixture.clock.addingTimeInterval(100)

        _ = await fixture.acquire(.lease, id: "job", ttl: 3600)
        #expect(try #require(fixture.lease("job")).expiresAt == fixture.clock.addingTimeInterval(3600))
    }

    @Test func reacquireUnionsTheLevel() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 600)
        #expect(try #require(fixture.lease("job")).level == .system)

        _ = await fixture.acquire(.lease, id: "job", level: "display", ttl: 600)
        #expect(try #require(fixture.lease("job")).level == AwakeLevel(display: true, lid: false))

        let response = await fixture.acquire(.lease, id: "job", level: "system", ttl: 600)
        #expect(acquireResult(response)?.lease.level == "display")
        #expect(try #require(fixture.lease("job")).level == AwakeLevel(display: true, lid: false))
    }

    @Test func reacquireMayAddLidWhenBounded() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", level: "display", ttl: 600)
        let response = await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600)
        #expect(acquireResult(response)?.lease.level == "display,lid")
        #expect(try #require(fixture.lease("job")).level == AwakeLevel(display: true, lid: true))
    }

    @Test func reacquireKeepsReasonAndOwnerUnlessGiven() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 600, reason: "building", agent: "codex")

        _ = await fixture.acquire(.lease, id: "job", ttl: 600)
        var lease = try #require(fixture.lease("job"))
        #expect(lease.reason == "building")
        #expect(lease.owner == .agent(name: "codex"))

        _ = await fixture.acquire(.lease, id: "job", ttl: 600, reason: "testing", agent: "claude")
        lease = try #require(fixture.lease("job"))
        #expect(lease.reason == "testing")
        #expect(lease.owner == .agent(name: "claude"))
    }

    @Test func reacquireKeepsReasonUnlessGiven() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 600, reason: "building")
        _ = await fixture.acquire(.lease, id: "job", ttl: 600)
        #expect(try #require(fixture.lease("job")).reason == "building")
        _ = await fixture.acquire(.lease, id: "job", ttl: 600, reason: "testing")
        #expect(try #require(fixture.lease("job")).reason == "testing")
    }

    @Test func reacquireCapStillApplies() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 3600)
        let response = await fixture.acquire(.lease, id: "job", ttl: 6 * 3600)
        #expect(response.ok)
        #expect(try #require(fixture.lease("job")).expiresAt == fixture.clock.addingTimeInterval(4 * 3600))
        #expect(acquireResult(response)?.clamped == true)
    }

    @Test func reacquireOfExpiredLeaseStartsFresh() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", level: "display", ttl: 600, watchPid: 4242, reason: "building")
        // Expired, but not yet ticked away.
        fixture.knobs.clock.addTimeInterval(601)

        let response = await fixture.acquire(.lease, id: "job", ttl: 600)

        #expect(response.ok)
        let lease = try #require(fixture.lease("job"))
        #expect(lease.watch == nil)
        #expect(lease.level == .system)
        #expect(lease.reason == "job")
        #expect(lease.expiresAt == fixture.clock.addingTimeInterval(600))
    }

    @Test func rawReacquireOfWatchedLeaseStillNeedsAnEnd() async throws {
        let fixture = RequestFixture.agent(children: [300])
        _ = await fixture.acquire(.lease, id: "job", watchPid: 300)

        // A raw wire client, not the CLI, which would refuse this itself.
        let response = await fixture.acquire(.lease, id: "job")

        #expect(wireFailure(response) == WireError(code: .badRequest, message: "A lease needs --ttl or --watch-pid"))
        #expect(try #require(fixture.lease("job")).watch?.pid == 300)
    }

    @Test func renewStillResetsTheLength() async throws {
        let fixture = RequestFixture()
        _ = await fixture.acquire(.lease, id: "job", ttl: 3600)
        _ = await fixture.renew("job", ttl: 600)
        #expect(try #require(fixture.lease("job")).expiresAt == fixture.clock.addingTimeInterval(600))
    }
}

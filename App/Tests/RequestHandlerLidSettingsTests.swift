import AwakeKit
import Foundation
import MooringIPC
import Testing
@testable import Mooring

/// Never and "Keep working with the lid closed: off" take lid mode back from live agent leases (stage 2c-1 fixes).
@MainActor
struct RequestHandlerLidSettingsTests {
    /// A person's acquire through the same handler: pid 300 isn't under an agent.
    private func asPerson(
        _ fixture: RequestFixture, _ kind: AcquireKind, id: String? = nil, level: String? = nil, ttl: Double? = nil
    ) async -> Response {
        let args = AcquireArgs(kind: kind, id: id, level: level, ttl: ttl, watchPid: nil, reason: nil, agent: nil)
        return await fixture.handler.handle(
            Request(v: 1, id: "r2", op: .acquire, args: .acquire(args)), from: Caller(uid: 501, pid: 300)
        )
    }

    @Test func neverRemovesLidFromAReacquiredNamedLease() async throws {
        let fixture = RequestFixture.agent()
        #expect(await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600).ok)
        #expect(try #require(fixture.lease("job")).level == lidOnly)
        fixture.knobs.settings.agentLidApproval = .never

        let again = await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600)

        #expect(wireFailure(again) == denied("Lid mode not approved (lid mode for agents is set to Never)"))
        #expect(try #require(fixture.lease("job")).level == .system)
    }

    @Test func sessionLidOffDropsLidOnNextHook() async throws {
        // Off: the next prompt re-acquires at system level rather than merging lid back in.
        let off = RequestFixture()
        _ = await off.hook("UserPromptSubmit")
        #expect(try #require(off.lease("claude-s1")).level == lidOnly)
        off.knobs.settings.agentSessionLid = false
        _ = await off.hook("UserPromptSubmit")
        #expect(try #require(off.lease("claude-s1")).level == .system)

        // Never: a renewal drops it too.
        let never = RequestFixture()
        _ = await never.hook("UserPromptSubmit")
        never.knobs.settings.agentLidApproval = .never
        _ = await never.hook("PostToolUse")
        #expect(try #require(never.lease("claude-s1")).level == .system)
    }

    @Test func switchingToNeverDropsAgentLidImmediately() async throws {
        let fixture = RequestFixture.agent()
        fixture.approver.answers = [.allowOnce]
        _ = await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600)
        _ = await fixture.hook("UserPromptSubmit")
        #expect(await fixture.acquire(.on, level: "lid").ok)
        #expect(try #require(fixture.lease("menu")).level == lidOnly)

        fixture.knobs.settings.agentLidApproval = .never
        fixture.handler.applyLidSettings()

        #expect(try #require(fixture.lease("job")).level == .system)
        #expect(try #require(fixture.lease("claude-s1")).level == .system)
        #expect(try #require(fixture.lease("menu")).level == .system)
    }

    @Test func switchingToNeverLeavesAPersonsLidSession() async throws {
        let fixture = RequestFixture.agent()
        #expect(await asPerson(fixture, .on, level: "lid").ok)
        #expect(await asPerson(fixture, .lease, id: "mine", level: "lid", ttl: 600).ok)
        fixture.engine.startLidSession()
        _ = await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600)

        fixture.knobs.settings.agentLidApproval = .never
        fixture.handler.applyLidSettings()

        #expect(try #require(fixture.lease("menu")).level == lidOnly)
        #expect(try #require(fixture.lease("mine")).level == lidOnly)
        #expect(try #require(fixture.lease(AwakeEngine.lidSessionID)).level == lidOnly)
        #expect(try #require(fixture.lease("job")).level == .system)
    }

    @Test func sessionLidOffLeavesOtherAgentLeases() async throws {
        let fixture = RequestFixture.agent()
        _ = await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600)
        _ = await fixture.hook("UserPromptSubmit")

        fixture.knobs.settings.agentSessionLid = false
        fixture.handler.applyLidSettings()

        #expect(try #require(fixture.lease("claude-s1")).level == .system)
        #expect(try #require(fixture.lease("job")).level == lidOnly)
    }
}

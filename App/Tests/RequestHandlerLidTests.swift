import AwakeKit
import Foundation
import MooringIPC
import Testing
@testable import Mooring

extension RequestFixture {
    /// A fixture whose caller (pid 200) runs under `claude`, so it counts as Claude Code.
    static func agent() -> RequestFixture {
        RequestFixture(table: FakeProcessTable([(200, "sh"), (100, "claude")]), callerPID: 200)
    }

    /// Waits until `condition` holds (or about 2 s pass), for work a request starts in the background.
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2000 where !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

private let lidOnly = AwakeLevel(display: false, lid: true)

private func denied(_ message: String) -> WireError {
    WireError(code: .denied, message: message)
}

/// Lid mode for agents: who is asked, and what each answer does (stage 2c-1 spec).
@MainActor
struct RequestHandlerLidTests {
    // MARK: - people and the setting

    @Test func terminalLidIsTrustedUnderNever() async throws {
        let fixture = RequestFixture()
        fixture.knobs.settings.agentLidApproval = .never

        let response = await fixture.acquire(.on, level: "lid")

        #expect(response.ok)
        #expect(try #require(fixture.lease("menu")).level == lidOnly)
        #expect(fixture.approver.calls.isEmpty)
    }

    @Test func neverRefusesAgentLid() async throws {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .never
        fixture.knobs.settings.agentLidAlwaysAllowed = ["Claude Code"]

        let response = await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600)

        #expect(wireFailure(response) == denied("Lid mode not approved (lid mode for agents is set to Never)"))
        #expect(try #require(fixture.lease("job")).level == .system)
        #expect(fixture.approver.calls.isEmpty)
    }

    @Test func boundedNamedLidLeaseIsAllowedWithoutAsking() async throws {
        let fixture = RequestFixture.agent()

        let lease = await fixture.acquire(.lease, id: "job-x", level: "lid", ttl: 1800, watchPid: 4242)
        let anchor = await fixture.acquire(.anchor, level: "lid", watchPid: 4343)

        #expect(lease.ok)
        #expect(anchor.ok)
        #expect(try #require(fixture.lease("job-x")).level == lidOnly)
        #expect(try #require(fixture.lease("anchor-4343")).level == lidOnly)
        #expect(fixture.approver.calls.isEmpty)
    }

    // MARK: - the answers

    @Test func agentOpenEndedOnAsksAndAllowAddsLid() async throws {
        let fixture = RequestFixture.agent()
        fixture.approver.answers = [.allowOnce]

        let response = await fixture.acquire(.on, level: "lid")

        #expect(response.ok)
        #expect(acquireResult(response)?.lease.level == "lid")
        #expect(try #require(fixture.lease("menu")).level == lidOnly)
        #expect(fixture.approver.calls == [
            FakeLidApprover.Call(leaseID: "menu", agent: "Claude Code", body: "\(AwakeEngine.menuReason) · with no end time")
        ])
    }

    @Test func boundedOnDoesNotAskButOpenEndedClickDefaultDoes() async throws {
        let bounded = RequestFixture.agent()
        _ = await bounded.acquire(.on, level: "lid", ttl: 1800)
        #expect(bounded.approver.calls.isEmpty)

        let clickDefault = RequestFixture.agent()
        clickDefault.knobs.settings.clickLevel = lidOnly
        clickDefault.approver.answers = [.allowOnce]
        _ = await clickDefault.acquire(.on)
        #expect(clickDefault.approver.calls.count == 1)
        #expect(try #require(clickDefault.lease("menu")).level == lidOnly)
    }

    @Test func denyKeepsSystemAndRepliesDenied() async throws {
        let fixture = RequestFixture.agent()
        fixture.approver.answers = [.deny]

        let response = await fixture.acquire(.on, level: "display,lid")

        #expect(wireFailure(response) == denied("Lid mode not approved (denied)"))
        #expect(try #require(fixture.lease("menu")).level == .screenOn)
    }

    @Test func timeoutRepliesNoAnswer() async throws {
        let fixture = RequestFixture.agent()
        fixture.approver.answers = [.timeout]

        let response = await fixture.acquire(.on, level: "lid")

        #expect(wireFailure(response) == denied("Lid mode not approved (no answer in 60 s)"))
        #expect(try #require(fixture.lease("menu")).level == .system)
    }

    @Test func unavailableNotificationsRefuseImmediately() async throws {
        let fixture = RequestFixture.agent()
        fixture.approver.answers = [.unavailable]

        let response = await fixture.acquire(.on, level: "lid")

        #expect(wireFailure(response) == denied("Turn on notifications for Mooring in System Settings to approve lid mode"))
        #expect(try #require(fixture.lease("menu")).level == .system)
    }

    @Test func alwaysAllowPersistsAndSkipsTheNextAsk() async throws {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidAlwaysAllowed = ["Codex"]
        fixture.approver.answers = [.alwaysAllow]

        let first = await fixture.acquire(.on, level: "lid")
        _ = await fixture.release(.off)
        let second = await fixture.acquire(.on, level: "lid")

        #expect(first.ok)
        #expect(second.ok)
        #expect(fixture.knobs.settings.agentLidAlwaysAllowed == ["Codex", "Claude Code"])
        #expect(try #require(fixture.lease("menu")).level == lidOnly)
        #expect(fixture.approver.calls.count == 1)
    }

    // MARK: - asking once

    @Test func deniedLeaseIsNotReaskedUntilReleased() async throws {
        let fixture = RequestFixture.agent()
        fixture.approver.answers = [.deny, .allowOnce]

        _ = await fixture.acquire(.on, level: "lid")
        let again = await fixture.acquire(.on, level: "lid")
        #expect(wireFailure(again) == denied("Lid mode not approved (denied)"))
        #expect(fixture.approver.calls.count == 1)

        _ = await fixture.release(.off)
        let afterRelease = await fixture.acquire(.on, level: "lid")
        #expect(afterRelease.ok)
        #expect(fixture.approver.calls.count == 2)
        #expect(try #require(fixture.lease("menu")).level == lidOnly)
    }

    @Test func sameLeaseIsNotAskedTwice() async throws {
        let fixture = RequestFixture.agent()
        fixture.approver.holds = true

        let first = Task { await fixture.acquire(.on, level: "lid") }
        await fixture.approver.waitForCalls(1)
        let second = await fixture.acquire(.on, level: "lid")

        #expect(wireFailure(second) == denied("Lid mode not approved (waiting for your answer to an earlier request)"))
        #expect(fixture.approver.calls.count == 1)
        fixture.approver.resolve("menu", with: .allowOnce)
        #expect(await first.value.ok)
        #expect(try #require(fixture.lease("menu")).level == lidOnly)
    }

    @Test func concurrentAsksResolveIndependently() async throws {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .alwaysAsk
        fixture.approver.holds = true

        let jobA = Task { await fixture.acquire(.lease, id: "job-a", level: "lid", ttl: 600) }
        await fixture.approver.waitForCalls(1)
        let jobB = Task { await fixture.acquire(.lease, id: "job-b", level: "lid", ttl: 600) }
        await fixture.approver.waitForCalls(2)
        #expect(fixture.approver.pending == ["job-a", "job-b"])

        fixture.approver.resolve("job-b", with: .allowOnce)
        #expect(await jobB.value.ok)
        fixture.approver.resolve("job-a", with: .deny)
        #expect(wireFailure(await jobA.value) == denied("Lid mode not approved (denied)"))

        #expect(try #require(fixture.lease("job-a")).level == .system)
        #expect(try #require(fixture.lease("job-b")).level == lidOnly)
        #expect(fixture.approver.calls.map(\.body) == ["job-a · for 10m", "job-b · for 10m"])
    }

    @Test func allowAfterReleaseDoesNothing() async {
        let fixture = RequestFixture.agent()
        fixture.knobs.settings.agentLidApproval = .alwaysAsk
        fixture.approver.holds = true

        let ask = Task { await fixture.acquire(.lease, id: "job", level: "lid", ttl: 600) }
        await fixture.approver.waitForCalls(1)
        _ = await fixture.release(.lease, id: "job")
        fixture.approver.resolve("job", with: .allowOnce)

        #expect(wireFailure(await ask.value)?.code == .notFound)
        #expect(fixture.lease("job") == nil)
    }

    // MARK: - Claude Code sessions

    @Test func sessionLidFollowsTheSwitch() async throws {
        let switchedOn = RequestFixture()
        _ = await switchedOn.hook("UserPromptSubmit")
        #expect(try #require(switchedOn.lease("claude-s1")).level == lidOnly)

        let off = RequestFixture()
        off.knobs.settings.agentSessionLid = false
        _ = await off.hook("UserPromptSubmit")
        #expect(try #require(off.lease("claude-s1")).level == .system)

        let never = RequestFixture()
        never.knobs.settings.agentLidApproval = .never
        _ = await never.hook("UserPromptSubmit")
        #expect(try #require(never.lease("claude-s1")).level == .system)
        #expect(switchedOn.approver.calls.isEmpty && off.approver.calls.isEmpty && never.approver.calls.isEmpty)
    }

    @Test func hookUnderAlwaysAskStartsWithoutLidAndUpgradesOnAllow() async throws {
        let fixture = RequestFixture()
        fixture.knobs.settings.agentLidApproval = .alwaysAsk
        fixture.approver.holds = true

        let response = await fixture.hook("UserPromptSubmit")

        #expect(response.ok)
        #expect(try #require(fixture.lease("claude-s1")).level == .system)
        await fixture.approver.waitForCalls(1)
        #expect(fixture.approver.calls.first?.agent == "Claude Code")
        _ = await fixture.hook("UserPromptSubmit")
        #expect(fixture.approver.calls.count == 1)

        fixture.approver.resolve("claude-s1", with: .allowOnce)
        await fixture.waitUntil { fixture.lease("claude-s1")?.level == lidOnly }
        #expect(try #require(fixture.lease("claude-s1")).level == lidOnly)
    }

    // MARK: - status

    @Test func statusReportsPendingAndNotifications() async throws {
        let fixture = RequestFixture.agent()
        fixture.approver.holds = true
        fixture.knobs.notifications = "notDetermined"

        let ask = Task { await fixture.acquire(.on, level: "lid") }
        await fixture.approver.waitForCalls(1)
        let response = await fixture.send(.status)

        guard case .status(let status)? = response.result else { Issue.record("no status"); return }
        #expect(status.leases.first { $0.id == "menu" }?.pendingApproval == true)
        #expect(status.notifications == "notDetermined")
        #expect(status.agentLidApproval == "askWhenOpenEnded")
        fixture.approver.resolve("menu", with: .deny)
        _ = await ask.value
    }
}

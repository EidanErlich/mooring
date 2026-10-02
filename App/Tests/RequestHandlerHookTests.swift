import AwakeKit
import Foundation
import MooringIPC
import Testing
@testable import Mooring

extension RequestFixture {
    /// Sends a hook event for `sessionId`, with the working directory and watched pid a real session would give.
    func hook(
        _ event: String, session sessionId: String = "s1", cwd: String? = "/Users/test/mooring", watchPid: Int32? = 4242,
        notificationType: String? = nil, agentID: String? = nil, agentType: String? = nil, runningBackgroundTasks: Int? = nil,
        toolTimeout: Double? = nil
    ) async -> Response {
        await send(.hook(HookArgs(
            event: event, sessionId: sessionId, cwd: cwd, notificationType: notificationType, agentID: agentID,
            agentType: agentType, runningBackgroundTasks: runningBackgroundTasks, watchPid: watchPid, toolTimeout: toolTimeout
        )))
    }

    /// Moves the clock forward.
    func advance(_ seconds: TimeInterval) {
        knobs.clock = knobs.clock.addingTimeInterval(seconds)
    }
}

private func hookAction(_ response: Response) -> String? {
    if case .hook(let result)? = response.result { result.action } else { nil }
}

/// How the app turns Claude Code hook events into the session's lease.
@MainActor
struct RequestHandlerHookTests {
    private func expiry(_ fixture: RequestFixture, _ id: String = "claude-s1") throws -> TimeInterval {
        try #require(fixture.lease(id)?.expiresAt).timeIntervalSince(fixture.clock)
    }

    @Test func promptCreatesTheSessionLease() async throws {
        let fixture = RequestFixture()
        let response = await fixture.hook("UserPromptSubmit")
        #expect(response.ok)
        #expect(hookAction(response) == "acquire")
        let lease = try #require(fixture.lease("claude-s1"))
        #expect(lease.owner == .agent(name: "Claude Code"))
        #expect(lease.reason == "Claude Code · mooring")
        #expect(lease.watch?.pid == 4242)
        #expect(abs(try expiry(fixture) - 900) < 0.001)
    }

    @Test func reasonWithoutCwdSaysSession() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit", session: "a", cwd: nil)
        _ = await fixture.hook("UserPromptSubmit", session: "b", cwd: "")
        _ = await fixture.hook("UserPromptSubmit", session: "c", cwd: "/")
        for id in ["claude-a", "claude-b", "claude-c"] {
            #expect(try #require(fixture.lease(id)).reason == "Claude Code · session")
        }
    }

    @Test func toolEventRenewsTo15Minutes() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        fixture.advance(600)
        let response = await fixture.hook("PostToolUse")
        #expect(hookAction(response) == "renew")
        #expect(abs(try expiry(fixture) - 900) < 0.001)
    }

    @Test func longBashCallKeepsTheLease() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        let response = await fixture.hook("PreToolUse", toolTimeout: 1200)
        #expect(hookAction(response) == "renew")
        #expect(abs(try expiry(fixture) - 1260) < 0.001)
        // 20 minutes into the call nothing has fired since, and the lease is still there.
        fixture.advance(1200)
        fixture.engine.tick()
        #expect(fixture.lease("claude-s1") != nil)
        // The call ends and the next event is back to 15 minutes.
        _ = await fixture.hook("PostToolUse")
        #expect(abs(try expiry(fixture) - 900) < 0.001)
    }

    @Test func shortToolEventDoesNotCutALongBashHold() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        _ = await fixture.hook("PreToolUse", toolTimeout: 1200)
        #expect(abs(try expiry(fixture) - 1260) < 0.001)
        // A parallel short tool finishes while the long call runs: the hold stays where it was.
        fixture.advance(5)
        let response = await fixture.hook("PostToolUse")
        #expect(hookAction(response) == "renew")
        #expect(abs(try expiry(fixture) - 1255) < 0.001)
    }

    @Test func renewExtendsWhenShorter() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        fixture.advance(600)
        // 300 s are left, so a 15 minute renew extends the hold.
        _ = await fixture.hook("PostToolUse")
        #expect(abs(try expiry(fixture) - 900) < 0.001)
        // A Bash timeout shorter than 15 minutes (+1 min) also extends from a shorter remainder.
        fixture.advance(800)
        _ = await fixture.hook("PreToolUse", toolTimeout: 1200)
        #expect(abs(try expiry(fixture) - 1260) < 0.001)
    }

    @Test func waitingStillResets() async throws {
        let fixture = RequestFixture()
        fixture.knobs.settings.agentWaitingTimeout = 600
        _ = await fixture.hook("UserPromptSubmit")
        _ = await fixture.hook("PreToolUse", toolTimeout: 1200)
        #expect(abs(try expiry(fixture) - 1260) < 0.001)
        let response = await fixture.hook("PermissionRequest")
        #expect(hookAction(response) == "waiting")
        #expect(abs(try expiry(fixture) - 600) < 0.001)
    }

    @Test func stopAfterLongHoldStillReleasesIn2Minutes() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        _ = await fixture.hook("PreToolUse", toolTimeout: 1200)
        fixture.advance(30)
        _ = await fixture.hook("PostToolUse")
        let response = await fixture.hook("Stop")
        #expect(hookAction(response) == "releaseAfter")
        #expect(abs(try expiry(fixture) - 120) < 0.001)
    }

    @Test func longBashCallWithoutLeaseAcquiresForItsTimeout() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("PreToolUse", toolTimeout: 1200)
        #expect(fixture.lease("claude-s1")?.watch?.pid == 4242)
        #expect(abs(try expiry(fixture) - 1260) < 0.001)
    }

    @Test func toolEventAfterReleaseReacquires() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        _ = await fixture.hook("SessionEnd")
        #expect(fixture.lease("claude-s1") == nil)
        let response = await fixture.hook("PreToolUse")
        #expect(hookAction(response) == "acquire")
        #expect(fixture.lease("claude-s1")?.watch?.pid == 4242)
        #expect(abs(try expiry(fixture) - 900) < 0.001)
    }

    @Test func permissionPromptUsesTheWaitingTimeout() async throws {
        let fixture = RequestFixture()
        fixture.knobs.settings.agentWaitingTimeout = 3600
        _ = await fixture.hook("UserPromptSubmit")
        let response = await fixture.hook("PermissionRequest")
        #expect(hookAction(response) == "waiting")
        #expect(abs(try expiry(fixture) - 3600) < 0.001)
        // The Notification for the same prompt changes nothing.
        _ = await fixture.hook("Notification", notificationType: "permission_prompt")
        #expect(abs(try expiry(fixture) - 3600) < 0.001)
    }

    @Test func permissionPromptWithoutLeaseAcquiresForTheWait() async throws {
        let fixture = RequestFixture()
        fixture.knobs.settings.agentWaitingTimeout = 1800
        _ = await fixture.hook("PermissionRequest")
        let lease = try #require(fixture.lease("claude-s1"))
        #expect(lease.watch?.pid == 4242)
        #expect(abs(try expiry(fixture) - 1800) < 0.001)
    }

    @Test func stopLeavesTwoMinutesThenTickRemoves() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        fixture.advance(10)
        let response = await fixture.hook("Stop")
        #expect(hookAction(response) == "releaseAfter")
        #expect(abs(try expiry(fixture) - 120) < 0.001)
        fixture.advance(121)
        fixture.engine.tick()
        #expect(fixture.lease("claude-s1") == nil)
    }

    @Test func stopThenIdleNotificationStillSleepsAfterGrace() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        _ = await fixture.hook("Stop")
        fixture.advance(30)
        let response = await fixture.hook("Notification", notificationType: "idle_prompt")
        #expect(hookAction(response) == "ignore")
        #expect(abs(try expiry(fixture) - 90) < 0.001)
    }

    @Test func promptDuringGraceRestores15Minutes() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        _ = await fixture.hook("Stop")
        fixture.advance(60)
        _ = await fixture.hook("UserPromptSubmit")
        #expect(abs(try expiry(fixture) - 900) < 0.001)
        #expect(fixture.lease("claude-s1")?.watch?.pid == 4242)
    }

    @Test func sessionEndReleasesNow() async {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        let response = await fixture.hook("SessionEnd")
        #expect(hookAction(response) == "releaseNow")
        #expect(fixture.lease("claude-s1") == nil)
    }

    @Test func twoSessionsAreIndependent() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit", session: "a")
        _ = await fixture.hook("UserPromptSubmit", session: "b")
        _ = await fixture.hook("SessionEnd", session: "a")
        #expect(fixture.lease("claude-a") == nil)
        #expect(fixture.lease("claude-b") != nil)
    }

    @Test func onlyWhenAskedCreatesNothing() async {
        let fixture = RequestFixture()
        fixture.knobs.settings.agentKeepAwake = .explicit
        let response = await fixture.hook("UserPromptSubmit")
        #expect(response.ok)
        #expect(hookAction(response) == "skipped")
        #expect(fixture.engine.leases.isEmpty)
    }

    @Test func invalidSessionIdIsBadRequest() async {
        let fixture = RequestFixture()
        let response = await fixture.hook("UserPromptSubmit", session: "../x")
        #expect(wireFailure(response)?.code == .badRequest)
        #expect(fixture.engine.leases.isEmpty)
    }

    @Test func stopWithRunningBackgroundTaskKeepsRenewing() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        fixture.advance(100)
        let response = await fixture.hook("Stop", runningBackgroundTasks: 1)
        #expect(hookAction(response) == "renew")
        #expect(abs(try expiry(fixture) - 900) < 0.001)
    }

    @Test func internalAgentAfterStopDoesNotRenew() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        _ = await fixture.hook("Stop")
        fixture.advance(50)
        let response = await fixture.hook("PreToolUse", agentID: "x", agentType: "")
        #expect(hookAction(response) == "ignore")
        #expect(abs(try expiry(fixture) - 70) < 0.001)
    }

    @Test func expiredLeaseCountsAsMissing() async throws {
        let fixture = RequestFixture()
        _ = await fixture.hook("UserPromptSubmit")
        fixture.advance(1000)
        // Expired but not yet ticked away: a tool event acquires afresh, and a Stop has nothing to shorten.
        #expect(fixture.lease("claude-s1") != nil)
        let stop = await fixture.hook("Stop")
        #expect(hookAction(stop) == "ignore")
        let response = await fixture.hook("PreToolUse")
        #expect(hookAction(response) == "acquire")
        #expect(abs(try expiry(fixture) - 900) < 0.001)
    }
}

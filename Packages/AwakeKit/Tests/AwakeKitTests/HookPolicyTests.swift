import AwakeKit
import Testing

struct HookPolicyTests {
    private func action(_ event: String, notificationType: String? = nil, agentID: String? = nil, agentType: String? = nil,
                        runningBackgroundTasks: Int? = nil, settings: AwakeSettings = AwakeSettings(),
                        leaseExists: Bool = true) -> HookAction {
        HookPolicy.action(HookEvent(name: event, notificationType: notificationType, agentID: agentID, agentType: agentType,
                                    runningBackgroundTasks: runningBackgroundTasks), settings: settings, leaseExists: leaseExists)
    }

    @Test func promptAcquires() {
        #expect(action("UserPromptSubmit", leaseExists: false) == .acquire)
        #expect(action("UserPromptSubmit", leaseExists: true) == .acquire)
    }

    @Test func toolEventsRenew() {
        for event in ["PreToolUse", "PostToolUse", "SubagentStart", "SubagentStop", "PreCompact"] {
            #expect(action(event) == .renew, "\(event)")
        }
    }

    @Test func postToolBatchAndSubagentStartRenew() {
        #expect(action("PostToolBatch") == .renew)
        #expect(action("SubagentStart") == .renew)
    }

    @Test func toolEventWithoutLeaseAcquires() {
        #expect(action("PreToolUse", leaseExists: false) == .acquire)
        #expect(action("PreCompact", leaseExists: false) == .acquire)
    }

    @Test func permissionPromptSetsTheWaitingTimeout() {
        var settings = AwakeSettings()
        settings.agentWaitingTimeout = 600
        #expect(action("Notification", notificationType: "permission_prompt", settings: settings) == .setExpiry(600))
    }

    @Test func permissionRequestSetsTheWaitingTimeout() {
        var settings = AwakeSettings()
        settings.agentWaitingTimeout = 600
        #expect(action("PermissionRequest", settings: settings) == .setExpiry(600))
    }

    @Test func idleNotificationIsIgnored() {
        #expect(action("Notification", notificationType: "idle_prompt") == .ignore)
    }

    @Test func otherNotificationsAreIgnored() {
        #expect(action("Notification", notificationType: "auth_success") == .ignore)
        #expect(action("Notification") == .ignore)
    }

    @Test func stopReleasesAfterGrace() {
        #expect(action("Stop") == .releaseAfter(120))
        #expect(HookPolicy.stopGrace == 120 && HookPolicy.activeTTL == 900)
    }

    @Test func stopWithRunningBackgroundTasksRenews() {
        #expect(action("Stop", runningBackgroundTasks: 2) == .renew)
        #expect(action("Stop", runningBackgroundTasks: 1, leaseExists: false) == .acquire)
    }

    @Test func stopWithZeroBackgroundTasksReleasesAfterGrace() {
        #expect(action("Stop", runningBackgroundTasks: 0) == .releaseAfter(120))
    }

    @Test func stopFailureReleasesAfterGrace() {
        #expect(action("StopFailure") == .releaseAfter(120))
        #expect(action("StopFailure", leaseExists: false) == .ignore)
        #expect(action("StopFailure", runningBackgroundTasks: 0) == .releaseAfter(120))
    }

    @Test func stopFailureWithBackgroundTasksRenews() {
        #expect(action("StopFailure", runningBackgroundTasks: 1) == .renew)
        #expect(action("StopFailure", runningBackgroundTasks: 1, leaseExists: false) == .acquire)
    }

    @Test func sessionEndReleasesNow() {
        #expect(action("SessionEnd") == .releaseNow)
    }

    @Test func endEventsWithoutLeaseAreIgnored() {
        #expect(action("Stop", leaseExists: false) == .ignore)
        #expect(action("SessionEnd", leaseExists: false) == .ignore)
    }

    @Test func unknownEventsAreIgnored() {
        for event in ["SessionStart", "FutureThing"] {
            #expect(action(event) == .ignore, "\(event)")
        }
    }

    @Test func internalAgentEventsAreIgnored() {
        for agentType in [nil, ""] as [String?] {
            for event in ["PreToolUse", "SubagentStop"] {
                for leaseExists in [true, false] {
                    #expect(action(event, agentID: "a1", agentType: agentType, leaseExists: leaseExists) == .ignore)
                }
            }
        }
    }

    @Test func realSubagentEventsRenew() {
        #expect(action("PreToolUse", agentID: "a1", agentType: "general-purpose") == .renew)
        #expect(action("SubagentStop", agentID: "a1", agentType: "general-purpose") == .renew)
    }

    @Test func onlyWhenAskedSkipsEverything() {
        var settings = AwakeSettings()
        settings.agentKeepAwake = .explicit
        let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolBatch", "SubagentStart", "SubagentStop",
                      "PreCompact", "PermissionRequest", "Notification", "Stop", "SessionEnd", "SessionStart", "FutureThing"]
        for event in events {
            #expect(action(event, settings: settings) == .skipped, "\(event)")
        }
        #expect(action("PreToolUse", agentID: "a1", settings: settings) == .skipped)
    }

    @Test func wireNames() {
        #expect(HookAction.acquire.wireName == "acquire")
        #expect(HookAction.renew.wireName == "renew")
        #expect(HookAction.setExpiry(60).wireName == "waiting")
        #expect(HookAction.releaseAfter(120).wireName == "releaseAfter")
        #expect(HookAction.releaseNow.wireName == "releaseNow")
        #expect(HookAction.ignore.wireName == "ignore")
        #expect(HookAction.skipped.wireName == "skipped")
    }
}

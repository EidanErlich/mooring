import AwakeKit
import Foundation
import Testing
@testable import Mooring

@MainActor
struct LidControllerTests {
    @Test func refreshReadsCurrentValue() async {
        let controller = LidController(helper: FakeLidHelper(sleepDisabled: true))
        await controller.settle()
        #expect(controller.applied == true)
    }

    @Test func applyConfirmsOnSuccess() async {
        let helper = FakeLidHelper()
        let controller = LidController(helper: helper)
        await controller.settle()
        controller.apply(true)
        #expect(controller.isBusy)
        await controller.settle()
        #expect(controller.applied == true)
        #expect(!controller.isBusy)
        #expect(helper.sleepDisabled)
    }

    @Test func failedApplyRereadsState() async {
        let helper = FakeLidHelper()
        let controller = LidController(helper: helper)
        await controller.settle()
        helper.failNextSet = true
        controller.apply(true)
        await controller.settle()
        #expect(controller.applied == false)
    }

    /// SleepDisabled = 1 left from before (a crash, 1a testing, a reboot in lid mode)
    /// is cleared on launch when no restored lease wants lid.
    @Test func launchResetClearsStaleSleepDisabled() async {
        let helper = FakeLidHelper(sleepDisabled: true)
        let controller = LidController(helper: helper)
        let engine = AwakeEngine(assertions: NullAssertions(), store: MemoryStore(), processes: NoProcesses(),
                                 lid: controller, settings: { AwakeSettings() })
        engine.restore()
        await controller.settle()   // the launch read finds 1, so the engine asks for 0
        await controller.settle()   // the reset completes
        #expect(helper.sleepDisabled == false)
        #expect(controller.applied == false)
    }

    /// A helper that restarted (crash, kickstart, reboot) lost lid mode; the heartbeat notices.
    @Test func heartbeatMismatchTriggersReapply() async {
        let helper = FakeLidHelper()
        let controller = LidController(helper: helper)
        await controller.settle()
        controller.apply(true)
        await controller.settle()
        helper.sleepDisabled = false
        var changed = false
        controller.onChange = { changed = true }
        await controller.heartbeatNow()
        #expect(controller.applied == false)
        #expect(changed)
    }

    @Test func unavailableHelperIsNotCalled() async {
        let helper = FakeLidHelper()
        helper.status = .requiresApproval
        let controller = LidController(helper: helper)
        controller.refresh()
        controller.apply(true)
        await controller.settle()
        #expect(!controller.isAvailable)
        #expect(helper.calls.isEmpty)
    }
}

@MainActor
struct LidShutdownTests {
    /// On quit, lid sleep is restored and the engine can't turn it back off,
    /// even though the lid lease is kept for the next launch.
    @Test func shutDownRestoresAndRefusesReenable() async {
        let helper = FakeLidHelper()
        let controller = LidController(helper: helper)
        let engine = AwakeEngine(assertions: NullAssertions(), store: MemoryStore(), processes: NoProcesses(),
                                 lid: controller, settings: { AwakeSettings() })
        await controller.settle()
        engine.setAllowLidClose(true)
        await controller.settle()
        #expect(helper.sleepDisabled)
        await controller.shutDown()
        #expect(helper.sleepDisabled == false)
        engine.tick()
        await controller.settle()
        #expect(helper.sleepDisabled == false)
        #expect(engine.wantsLid)
    }
}

@MainActor
struct LidReviewFixTests {
    /// Keeping a SleepDisabled = 1 found at launch must hand the (possibly restarted)
    /// helper ownership right away, not 30 s later, so its watchdog covers a crash.
    @Test func foundLidModeIsHeartbeatImmediately() async {
        let helper = FakeLidHelper(sleepDisabled: true)
        let controller = LidController(helper: helper)
        await controller.settle()
        #expect(helper.calls.contains("heartbeat"))
    }

    @Test func uninstallRestoresThenUnregisters() async {
        let helper = FakeLidHelper()
        let controller = LidController(helper: helper)
        await controller.settle()
        controller.apply(true)
        await controller.settle()
        try? await controller.uninstall()
        let set = helper.calls.lastIndex(of: "set false")
        let unregister = helper.calls.lastIndex(of: "unregister")
        #expect(set != nil && unregister != nil && set! < unregister!)
        #expect(controller.applied == nil)
        #expect(!controller.isAvailable)
    }

    /// With the helper down, uninstall still unregisters (it's how the user recovers).
    @Test func uninstallProceedsWhenRestoreFails() async {
        let helper = FakeLidHelper(sleepDisabled: true)
        let controller = LidController(helper: helper)
        await controller.settle()
        helper.failNextSet = true
        try? await controller.uninstall()
        #expect(helper.calls.contains("unregister"))
    }

    /// A helper that fails instantly must not make the engine retry in a tight loop;
    /// retries wait for the 5 s tick.
    @Test func brokenHelperIsNotHammered() async {
        let helper = BrokenLidHelper()
        let controller = LidController(helper: helper)
        let engine = AwakeEngine(assertions: NullAssertions(), store: MemoryStore(), processes: NoProcesses(),
                                 lid: controller, settings: { AwakeSettings() })
        engine.restore()
        for _ in 0..<20 {
            await controller.settle()
            await Task.yield()
        }
        #expect(helper.calls <= 3)
    }
}

@MainActor
struct LidSnappinessTests {
    /// A helper that restarts (kickstart, crash) must be re-checked at once, not at
    /// the next 30 s heartbeat: the stopping helper turned lid sleep back on.
    @Test func lostConnectionIsRecheckedImmediately() async {
        let helper = FakeLidHelper()
        let controller = LidController(helper: helper)
        await controller.settle()
        controller.apply(true)
        await controller.settle()
        helper.sleepDisabled = false
        helper.onConnectionLost?()
        await controller.settle()
        #expect(controller.applied == false)
    }

    /// A healthy helper answers in milliseconds; only a broken one ever waits this long.
    @Test func helperCallsTimeOutQuickly() {
        #expect(HelperClient.callTimeout == 3)
    }
}

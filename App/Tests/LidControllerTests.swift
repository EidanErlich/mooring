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

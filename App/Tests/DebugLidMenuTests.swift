#if DEBUG
import Testing
@testable import Mooring

struct DebugLidMenuTests {
    @Test func offersApprovalUntilTheHelperIsEnabled() {
        #expect(DebugLidMenuEntry.entries(for: .requiresApproval) == [
            .status(.requiresApproval), .approve,
            .disableLidSleep, .enableLidSleep, .readSleepDisabled,
            .separator, .quit
        ])
    }

    @Test func dropsApprovalOnceEnabled() {
        #expect(DebugLidMenuEntry.entries(for: .enabled) == [
            .status(.enabled),
            .disableLidSleep, .enableLidSleep, .readSleepDisabled,
            .separator, .quit
        ])
    }

    @Test(arguments: [HelperStatus.notRegistered, .requiresApproval, .notFound])
    func flipItemsAreDisabledUntilApproved(status: HelperStatus) {
        for entry in [DebugLidMenuEntry.disableLidSleep, .enableLidSleep, .readSleepDisabled] {
            #expect(!entry.isEnabled(for: status))
        }
        #expect(DebugLidMenuEntry.approve.isEnabled(for: status))
    }

    @Test func flipItemsAreEnabledOnceApproved() {
        for entry in [DebugLidMenuEntry.disableLidSleep, .enableLidSleep, .readSleepDisabled] {
            #expect(entry.isEnabled(for: .enabled))
        }
    }

    @Test func titlesMatchTheSpec() {
        #expect(DebugLidMenuEntry.status(.requiresApproval).title == "Helper: awaiting approval")
        #expect(DebugLidMenuEntry.status(.enabled).title == "Helper: enabled")
        #expect(DebugLidMenuEntry.approve.title == "Approve lid mode…")
        #expect(DebugLidMenuEntry.disableLidSleep.title == "Disable lid sleep")
        #expect(DebugLidMenuEntry.enableLidSleep.title == "Enable lid sleep")
        #expect(DebugLidMenuEntry.readSleepDisabled.title == "Read SleepDisabled")
        #expect(DebugLidMenuEntry.quit.title == "Quit Mooring")
    }
}
#endif

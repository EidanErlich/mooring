import AwakeKit
import Testing
@testable import Mooring

struct GuardrailNotifierTests {
    @Test func messagesUseTheConfiguredThresholds() {
        let settings = AwakeSettings()
        let lid = GuardrailNotifier.message(for: .lowBatteryLid, settings: settings)
        #expect(lid.title == "Lid mode paused")
        #expect(lid.body.contains("below 20%"))
        #expect(lid.body.contains("at 25%"))
        let all = GuardrailNotifier.message(for: .lowBatteryAll, settings: settings)
        #expect(all.title == "Mooring paused")
        #expect(all.body.contains("below 10%"))
        for suspension in [Suspension.lidNeedsAC, .lowBatteryLid, .lowBatteryAll, .thermal] {
            let message = GuardrailNotifier.message(for: suspension, settings: settings)
            #expect(!message.title.isEmpty && !message.body.isEmpty)
        }
    }
}

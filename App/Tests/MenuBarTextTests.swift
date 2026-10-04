import AwakeKit
import Testing
@testable import Mooring

struct MenuBarTextTests {
    @Test func timeLabelFormats() {
        #expect(MenuBarText.timeLabel(30) == "1m")
        #expect(MenuBarText.timeLabel(2520) == "42m")
        #expect(MenuBarText.timeLabel(3540) == "59m")
        #expect(MenuBarText.timeLabel(3600) == "1:00")
        #expect(MenuBarText.timeLabel(4320) == "1:12")
        #expect(MenuBarText.timeLabel(28800) == "8:00")
    }

    @Test func timeLabelNeverReadsZero() {
        #expect(MenuBarText.timeLabel(0) == "1m")
        #expect(MenuBarText.timeLabel(-90) == "1m")
    }

    @Test func accessibilitySentences() {
        let cases: [(MenuBarState, String)] = [
            (.off, "Mooring, off"),
            (.awake(lid: false, kind: .indefinite), "Mooring, on, until turned off"),
            (.awake(lid: false, kind: .task), "Mooring, on, while an app runs"),
            (.awake(lid: false, kind: .timed(4320)), "Mooring, on, 1 hour 12 minutes left"),
            (.awake(lid: true, kind: .timed(2520)), "Mooring, lid mode, 42 minutes left"),
            (.awake(lid: false, kind: .timed(nil)), "Mooring, on"),
            (.awake(lid: false, kind: .timed(3600)), "Mooring, on, 1 hour left"),
            (.attention(.suspension(.lowBatteryLid)), "Mooring needs attention: lid mode paused, battery low"),
            (.attention(.suspension(.thermal)), "Mooring needs attention: lid mode paused, Mac too warm"),
            (.attention(.suspension(.lidNeedsAC)), "Mooring needs attention: lid mode paused, needs power"),
            (.attention(.suspension(.lowBatteryAll)), "Mooring paused, battery low"),
            (.attention(.helperNeedsApproval), "Mooring needs attention: helper needs approval"),
            (.attention(.windowsNeedAccessibility), "Mooring needs attention: Windows needs Accessibility")
        ]
        for (menuState, sentence) in cases {
            #expect(MenuBarText.accessibilityLabel(for: menuState) == sentence)
        }
    }
}

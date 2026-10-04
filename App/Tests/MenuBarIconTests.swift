import AppKit
import AwakeKit
import Testing
@testable import Mooring

private let everyState: [MenuBarState] = [
    .off,
    .awake(lid: false, kind: .indefinite), .awake(lid: true, kind: .indefinite),
    .awake(lid: false, kind: .task), .awake(lid: true, kind: .task),
    .awake(lid: false, kind: .timed(4320)), .awake(lid: true, kind: .timed(4320)),
    .awake(lid: false, kind: .timed(nil)), .awake(lid: true, kind: .timed(nil)),
    .attention(.suspension(.lowBatteryLid)), .attention(.helperNeedsApproval), .attention(.windowsNeedAccessibility)
]

private func width(_ state: MenuBarState) -> CGFloat { MenuBarIcon.image(for: state).size.width }

struct MenuBarIconTests {
    @Test func everyStateIs18PointsTall() {
        for state in everyState {
            #expect(MenuBarIcon.image(for: state).size.height == 18)
        }
    }

    /// Template images are what let macOS tint the icon for light and dark menu bars;
    /// only the attention pill carries its own colour.
    @Test func onlyAttentionIsColoured() {
        for state in everyState {
            let isAttention = if case .attention = state { true } else { false }
            #expect(MenuBarIcon.image(for: state).isTemplate == !isAttention)
        }
    }

    @Test func pillGrowsWithItsContents() {
        #expect(width(.awake(lid: true, kind: .timed(4320))) > width(.awake(lid: false, kind: .timed(4320))))
        #expect(width(.awake(lid: false, kind: .timed(4320))) > width(.awake(lid: false, kind: .timed(nil))))
    }

    /// A countdown must not change the item's width within the same number of digits.
    @Test func sameMinuteCountSameWidth() {
        #expect(width(.awake(lid: false, kind: .timed(4320))) == width(.awake(lid: false, kind: .timed(4260))))
    }
}

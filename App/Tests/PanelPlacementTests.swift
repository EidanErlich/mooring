import AppKit
import Testing
@testable import Mooring

private let visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
private let panel = NSSize(width: 320, height: 400)

struct PanelPlacementTests {
    @Test func leftEdgeAlignsWithIconBelowMenuBar() {
        let origin = PanelPlacement.origin(below: NSRect(x: 600, y: 944, width: 30, height: 24), panelSize: panel, in: visible)
        #expect(origin == NSPoint(x: 600, y: 544))
    }

    @Test func clampsToRightEdge() {
        let origin = PanelPlacement.origin(below: NSRect(x: 1480, y: 944, width: 30, height: 24), panelSize: panel, in: visible)
        #expect(origin.x == 1192)
    }

    @Test func clampsToLeftEdge() {
        let origin = PanelPlacement.origin(below: NSRect(x: -10, y: 944, width: 30, height: 24), panelSize: panel, in: visible)
        #expect(origin.x == 0)
    }

    @Test func staysOnSecondaryScreen() {
        let second = NSRect(x: 1512, y: 0, width: 1920, height: 1055)
        let origin = PanelPlacement.origin(below: NSRect(x: 3400, y: 1055, width: 30, height: 24), panelSize: panel, in: second)
        #expect(origin.x == second.maxX - 320)
        #expect(origin.y == 655)
    }

    @Test func maxHeightIs70Percent() {
        #expect(PanelPlacement.maxHeight(in: visible) == 944 * 0.7)
    }
}

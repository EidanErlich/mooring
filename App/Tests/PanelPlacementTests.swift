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

    // Auto-hidden menu bar (docs/SPEC.md, "Dropdown and an auto-hidden menu bar").

    @Test func anchorsUnderTheIconWhileTheBarShows() {
        let button = NSRect(x: 1180, y: 1130, width: 56, height: 39)
        let screen = NSRect(x: 0, y: 0, width: 1800, height: 1169)
        #expect(PanelPlacement.anchor(buttonFrame: button, screenFrame: screen, menuBarShown: true) == button)
    }

    @Test func anchorsFlushToTheScreenTopWhileTheBarIsHidden() {
        let button = NSRect(x: 1180, y: 1130, width: 56, height: 39)
        let screen = NSRect(x: 0, y: 0, width: 1800, height: 1169)
        let anchor = PanelPlacement.anchor(buttonFrame: button, screenFrame: screen, menuBarShown: false)
        let origin = PanelPlacement.origin(below: anchor, panelSize: panel, in: NSRect(x: 0, y: 0, width: 1800, height: 1131))
        #expect(origin == NSPoint(x: 1180, y: 769))
    }

    @Test func barHidingClosesThePanelUnlessThePointerIsInIt() {
        #expect(PanelPlacement.response(menuBarShown: false, pointerInPanel: false) == .close)
        #expect(PanelPlacement.response(menuBarShown: false, pointerInPanel: true) == .moveFlush)
    }

    @Test func barReturningMovesThePanelBackUnderIt() {
        #expect(PanelPlacement.response(menuBarShown: true, pointerInPanel: false) == .moveUnderBar)
        #expect(PanelPlacement.response(menuBarShown: true, pointerInPanel: true) == .moveUnderBar)
    }
}

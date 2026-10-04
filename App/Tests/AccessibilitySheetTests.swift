import AppKit
import SwiftUI
import Testing
@testable import Mooring

@MainActor
struct AccessibilitySheetTests {
    @Test func copyTellsHowToAddMooring() {
        #expect(AccessibilitySheet.explanation
            == "Mooring moves and resizes other apps' windows. macOS calls this Accessibility.")
        #expect(AccessibilitySheet.listHint
            == "If Mooring isn't in the list, click + and choose Mooring in Applications.")
        let host = NSHostingView(rootView: AccessibilitySheet(openSettingsPane: {}, cancel: {}))
        #expect(host.fittingSize.width > 0 && host.fittingSize.height > 0)
    }

    /// A normal window at the main screen's top left, so System Settings, which opens centred, isn't covered.
    @Test func sheetWindowIsNormalLevelAtTopLeft() {
        let presenter = AccessibilitySheetWindow(controller: WindowsController.fake(.off))
        let window = presenter.makeWindow()
        defer { window.close() }
        #expect(window.level == .normal)
        #expect(AccessibilitySheetWindow.topLeft(in: NSRect(x: 0, y: 25, width: 1440, height: 875))
            == NSPoint(x: 20, y: 880))
        #expect(AccessibilitySheetWindow.topLeft(in: NSRect(x: -1920, y: 0, width: 1920, height: 1080))
            == NSPoint(x: -1900, y: 1060))
    }
}

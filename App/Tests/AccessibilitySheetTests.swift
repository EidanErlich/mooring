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
}

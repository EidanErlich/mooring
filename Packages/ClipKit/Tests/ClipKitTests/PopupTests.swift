import AppKit
import Defaults
import Testing
@testable import ClipKit

/// A stand-in for the app's popup window.
final class FakePopupPanel: NSPanel, PopupPanel {
    var isPresented = false
    private(set) var opened: [ClipSettings.PopupPosition] = []
    private(set) var closes = 0

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [], backing: .buffered, defer: true)
    }

    func open(height: CGFloat, at position: ClipSettings.PopupPosition) {
        opened.append(position)
        isPresented = true
    }

    func verticallyResize(to newHeight: CGFloat) {}

    override func close() {
        closes += 1
        isPresented = false
    }
}

extension ClipKitGlobalStateTests {
    @Suite
    @MainActor
    struct PopupTests {
        @Test func panelIsBuiltOnlyWhileRunning() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            var built = 0
            let panel = FakePopupPanel()
            kit.makePopupPanel = { _ in
                built += 1
                return panel
            }
            kit.openPopup()
            #expect(built == 0)

            Fixture.start(kit)
            #expect(built == 1)
            #expect(AppState.shared.panel === panel)
            kit.openPopup()
            kit.openPopup()  // already open
            #expect(panel.opened == [.cursor])

            kit.stop()
            #expect(panel.closes >= 1)
            #expect(AppState.shared.panel == nil)
            kit.openPopup()
            #expect(panel.opened == [.cursor])
        }

        @Test func popupOpensWhereTheSettingSays() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            let panel = FakePopupPanel()
            kit.makePopupPanel = { _ in panel }
            Fixture.start(kit)
            Defaults[.popupPosition] = .statusItem
            kit.openPopup()
            #expect(panel.opened == [.statusItem])
            kit.stop()
            Fixture.resetSettings()
        }

        /// "Quit" would quit Mooring, and there's no About.
        @Test func footerHasNoQuit() {
            #expect(Footer().items.map(\.title) == ["clear", "clear_all", "preferences"])
        }

        @Test func preferencesOpenMooringSettings() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            var opened = 0
            kit.openSettings = { opened += 1 }
            Fixture.start(kit)
            AppState.shared.openPreferences()
            #expect(opened == 1)
            kit.stop()
        }

        @Test func untrustedPopupShowsPasteHint() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let untrusted = Fixture.kit(pasteboard: scratch, trusted: { false })
            Fixture.start(untrusted)
            #expect(AppState.shared.pasteHint == "Paste with ⌘V. Allow Accessibility in Windows to paste automatically.")
            untrusted.stop()

            let trusted = Fixture.kit(pasteboard: scratch, trusted: { true })
            Fixture.start(trusted)
            #expect(AppState.shared.pasteHint == nil)
            trusted.stop()
        }
    }
}

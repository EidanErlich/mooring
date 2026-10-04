import AppKit
import ClipKit
import Foundation
import Testing
@testable import Mooring

// The dropdown's Clipboard › submenu, over a fake ClipKit.
@MainActor
struct ClipboardSubmenuTests {
    @MainActor
    final class Fixture {
        let settings: FakeClipboardSettings
        private(set) var kits: [FakeClipKit] = []
        private(set) var controller: ClipboardController!
        var entries: [ClipboardEntry] = []
        var optionHeld = false
        var dismissals = 0
        var pending: [() -> Void] = []
        var shortcutReads = 0
        /// What the clear alert answers, and how often it was shown.
        var clearAnswer = ClearConfirmation(confirmed: true)
        var clearAlerts = 0
        private(set) var submenu: ClipboardSubmenu!

        var kit: FakeClipKit? { kits.last }

        init(enabled: Bool) {
            settings = FakeClipboardSettings(enabled: enabled)
            controller = ClipboardController(
                settings: settings, storeURL: URL(filePath: "/dev/null/Storage.sqlite"),
                confirmClear: { [unowned self] in
                    clearAlerts += 1
                    return clearAnswer
                },
                makeKit: { [unowned self] _ in
                    let kit = FakeClipKit()
                    kit.entries = entries
                    kits.append(kit)
                    return kit
                })
            controller.launch()
            submenu = ClipboardSubmenu(
                clipboard: controller, model: DropdownModel(),
                dismiss: { [unowned self] in dismissals += 1 },
                afterClose: { [unowned self] in pending.append($0) },
                modifierFlags: { [unowned self] in optionHeld ? .option : [] },
                popupShortcut: { [unowned self] in
                    shortcutReads += 1
                    return "⇧⌘C"
                })
        }

        func open() {
            submenu.dropdownDidOpen()
        }

        func runPending() {
            let actions = pending
            pending = []
            actions.forEach { $0() }
        }
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    private func row(_ menu: NSMenu, _ title: String) -> ClipboardSubmenu.Row? {
        menu.items.first { $0.title == title }?.representedObject as? ClipboardSubmenu.Row
    }

    private static func entries(_ count: Int) -> [ClipboardEntry] {
        (1...count).map { ClipboardEntry(id: "item\($0)", title: "Copy \($0)") }
    }

    @Test func offShowsTurnOnOnly() throws {
        let fixture = Fixture(enabled: false)
        fixture.open()
        let menu = fixture.submenu.menu
        #expect(titles(menu) == ["Turn On…"])

        try #require(row(menu, "Turn On…")).action()
        #expect(!fixture.controller.isOn)  // the menu is still up
        #expect(fixture.pending.count == 1)
        fixture.runPending()
        #expect(fixture.controller.isOn)
        #expect(fixture.settings.clipboardEnabled)

        // The dropdown puts it after Windows.
        let dropdown = DropdownMenuTests().makeMenuAndEngine(clipboard: fixture.controller).0
        let ids = dropdown.root.items.map { $0.isSeparatorItem ? "-" : $0.identifier!.rawValue }
        #expect(ids == ["header", "-", "awake", "windows", "clipboard", "-", "settings", "quit"])
        #expect(dropdown.root.item(withTitle: "Clipboard")?.submenu === dropdown.clipboardSubmenu.menu)
    }

    @Test func onShowsRecentAndActions() throws {
        let fixture = Fixture(enabled: true)
        let long = String(repeating: "a", count: 60)
        fixture.kit?.entries = [ClipboardEntry(id: "pinned", title: "Pinned", isPinned: true),
                                ClipboardEntry(id: "long", title: long), ClipboardEntry(id: "lines", title: "one\ntwo")]
            + Self.entries(11)
        fixture.open()
        let menu = fixture.submenu.menu

        let items = [String(repeating: "a", count: 49) + "…", "one two"] + (1...8).map { "Copy \($0)" }
        // Pins stay in the popup; the newest unpinned items are numbered as the popup numbers them.
        #expect(titles(menu) == items + ["-", "Pause Recording", "Ignore Next Copy", "Clear", "-", "Search…"])
        #expect(row(menu, "Pinned") == nil)
        #expect(row(menu, "Copy 1")?.trailing == "⌘3")
        #expect(fixture.kit?.recentLimits.last == 10)
        let trailing = menu.items.prefix(10).map { ($0.representedObject as? ClipboardSubmenu.Row)?.trailing }
        #expect(trailing == (1...9).map { "⌘\($0)" } + [nil])
        #expect(row(menu, "Search…")?.trailing == "⇧⌘C")
        #expect(row(menu, "Pause Recording")?.checked == false)

        // Search… opens the popup once the menu has closed.
        try #require(row(menu, "Search…")).action()
        #expect(fixture.kit?.popupOpens == 0)
        fixture.runPending()
        #expect(fixture.kit?.popupOpens == 1)

        // Pause Recording toggles, with a checkmark while paused.
        try #require(row(menu, "Pause Recording")).action()
        #expect(fixture.kit?.isPaused == true)
        fixture.open()
        #expect(row(fixture.submenu.menu, "Pause Recording")?.checked == true)

        try #require(row(fixture.submenu.menu, "Ignore Next Copy")).action()
        #expect(fixture.kit?.ignoreNextCopies == 1)

        // Right after turning on, before history loads, there are no items yet.
        fixture.kit?.entries = []
        fixture.open()
        #expect(titles(fixture.submenu.menu) == ["Pause Recording", "Ignore Next Copy", "Clear", "-", "Search…"])
    }

    /// Clear and Clear All ask first, as the popup does, once the menu has closed.
    @Test func optionShowsClearAll() throws {
        let fixture = Fixture(enabled: true)
        let kit = try #require(fixture.kit)
        fixture.open()

        // Cancelling clears nothing.
        fixture.clearAnswer = ClearConfirmation(confirmed: false)
        try #require(row(fixture.submenu.menu, "Clear")).action()
        #expect(fixture.clearAlerts == 0 && fixture.pending.count == 1)  // the menu is still up
        fixture.runPending()
        #expect(fixture.clearAlerts == 1)
        #expect(kit.clears == [])

        // Confirming clears the unpinned items.
        fixture.clearAnswer = ClearConfirmation(confirmed: true)
        try #require(row(fixture.submenu.menu, "Clear")).action()
        fixture.runPending()
        #expect(fixture.clearAlerts == 2)
        #expect(kit.clears == [false])

        // With ⌥ held as it opens: Clear All, confirmed with "don't ask again".
        fixture.optionHeld = true
        fixture.open()
        #expect(row(fixture.submenu.menu, "Clear") == nil)
        fixture.clearAnswer = ClearConfirmation(confirmed: true, dontAskAgain: true)
        try #require(row(fixture.submenu.menu, "Clear All")).action()
        fixture.runPending()
        #expect(fixture.clearAlerts == 3)
        #expect(kit.clears == [false, true])
        #expect(kit.clearAlertSuppressed)

        // Suppressed: it clears without asking.
        fixture.clearAnswer = ClearConfirmation(confirmed: false)
        try #require(row(fixture.submenu.menu, "Clear All")).action()
        fixture.runPending()
        #expect(fixture.clearAlerts == 3)
        #expect(kit.clears == [false, true, true])
    }

    @Test func chooseItemCopies() throws {
        let fixture = Fixture(enabled: true)
        fixture.kit?.entries = Self.entries(3)
        fixture.open()
        try #require(row(fixture.submenu.menu, "Copy 2")).action()
        #expect(fixture.kit?.copies == ["item2"])
        #expect(fixture.dismissals == 1)
    }

    @Test func offNeverTouchesClipKit() throws {
        let fixture = Fixture(enabled: true)
        fixture.kit?.entries = Self.entries(3)
        fixture.open()
        let rows = fixture.submenu.menu.items.compactMap { $0.representedObject as? ClipboardSubmenu.Row }
        fixture.controller.turnOff()
        let kit = try #require(fixture.kit)
        let touchesWhenOff = kit.touches
        let shortcutReads = fixture.shortcutReads
        let singletons = ClipKit.instantiatedSingletons

        fixture.open()
        #expect(titles(fixture.submenu.menu) == ["Turn On…"])
        // Rows from before it turned off, still on screen, do nothing either.
        rows.forEach { $0.action() }
        fixture.runPending()
        #expect(kit.touches == touchesWhenOff)
        #expect(fixture.shortcutReads == shortcutReads)
        #expect(fixture.kits.count == 1)
        #expect(!fixture.controller.isOn)
        #expect(ClipKit.instantiatedSingletons == singletons)
    }
}

extension ClipKitGlobalStateTests {
    @Suite
    @MainActor
    struct ClipboardPanelTests {
        /// The panel's content comes from `popupView()`, which is empty while ClipKit isn't running:
        /// building, laying out and closing the panel creates none of Maccy's state.
        @Test func panelFromAStoppedKitBuildsNothing() {
            let singletons = ClipKit.instantiatedSingletons
            let kit = ClipKit(storeURL: nil, inMemory: true)
            let panel = ClipboardPanel(kit: kit, statusBarButton: nil)
            panel.contentView?.layoutSubtreeIfNeeded()
            #expect(!panel.isPresented)
            #expect(panel.canBecomeKey)
            #expect(panel.level == .screenSaver)
            #expect(panel.styleMask.contains(.nonactivatingPanel))
            panel.close()
            #expect(!kit.isRunning)
            #expect(ClipKit.instantiatedSingletons == singletons)
        }
    }
}

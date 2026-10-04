import AppKit
import ClipKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Mooring

/// ClipKit's settings in memory, counting every read and write.
@MainActor
final class FakeClipboardSettingsAccess {
    var values: ClipSettings
    private(set) var reads = 0
    private(set) var writes: [ClipSettings] = []

    init(_ values: ClipSettings = .fixture) {
        self.values = values
    }

    var access: ClipboardSettingsAccess {
        ClipboardSettingsAccess(
            read: { self.reads += 1; return self.values },
            write: { self.writes.append($0); self.values = $0 })
    }
}

extension ClipSettings {
    static let fixture = ClipSettings(
        historySize: 200, clearOnQuit: false, pasteByDefault: false, removeFormattingByDefault: false,
        ignoredApps: ["com.example.vault"], ignoreAllAppsExceptListed: false,
        ignoredTypes: ["com.example.secret"], ignoreRegexes: ["^\\d{16}$"], recordUniversalClipboard: false,
        popupPosition: .cursor, pinsPosition: .top, searchVisibility: .always, showPreview: true,
        previewDelayMilliseconds: 1500, imageMaxHeight: 40)
}

/// Stands in for the hotkey recorder, counting how often one is built.
@MainActor
private final class CountingRecorder {
    private(set) var built = 0

    func build() -> AnyView {
        built += 1
        return AnyView(Text("recorder"))
    }
}

private let clipboardPages: [SettingsPage] = [.clipboardHistory, .clipboardIgnoreRules, .clipboardAppearance]

extension ClipKitGlobalStateTests {
    @Suite
    @MainActor
    struct ClipboardSettingsPageTests {
        private func controller(isOn: Bool) -> ClipboardController {
            let controller = ClipboardController(
                settings: FakeClipboardSettings(enabled: isOn), storeURL: URL(filePath: "/dev/null/Storage.sqlite"),
                makeKit: { _ in FakeClipKit() })
            controller.launch()
            #expect(controller.isOn == isOn)
            return controller
        }

        /// Off means off: each page is the banner, no ClipKit settings are read, no recorder is built.
        @Test func offPagesShowBannerOnly() {
            let singletons = ClipKit.instantiatedSingletons
            let fake = FakeClipboardSettingsAccess()
            let recorder = CountingRecorder()
            let clipboard = controller(isOn: false)
            for page in clipboardPages {
                #expect(page.clipboardContent(isOn: false) == .offBanner)
                let size = layOut(ClipboardSettingsPage(
                    page: page, clipboard: clipboard, access: fake.access, chooseApp: { nil }, recorder: recorder.build))
                #expect(size.width > 0 && size.height > 0, "\(page)")
            }
            #expect(fake.reads == 0)
            #expect(recorder.built == 0)
            #expect(ClipKit.instantiatedSingletons == singletons)
            #expect(ClipboardSettingsPage.offTitle == "Clipboard is off")
            #expect(WindowsPageBanner.turnOnTitle == "Turn On…")
        }

        @Test func onPagesLayOutAndOnlyHistoryRecordsTheHotkey() {
            let fake = FakeClipboardSettingsAccess()
            let recorder = CountingRecorder()
            let clipboard = controller(isOn: true)
            for page in clipboardPages {
                #expect(page.clipboardContent(isOn: true) == .page(page))
                let size = layOut(ClipboardSettingsPage(
                    page: page, clipboard: clipboard, access: fake.access, chooseApp: { nil }, recorder: recorder.build))
                #expect(size.width > 0 && size.height > 0, "\(page)")
            }
            #expect(fake.reads >= 3)
            #expect(recorder.built == 1)
            #expect(fake.writes.isEmpty)
        }

        /// The Shortcuts page reads the hotkey only while Clipboard is on, so no KeyboardShortcuts name is created while off.
        @Test func shortcutsPageNeverReadsTheHotkeyWhileOff() {
            let singletons = ClipKit.instantiatedSingletons
            var reads = 0
            let chord: @MainActor () -> String? = { reads += 1; return "⇧⌘C" }
            let off = controller(isOn: false)
            let size = layOut(ShortcutsSettingsPage(
                windows: .fake(.off), clipboard: off, clipboardChord: chord, keybinds: { [] }, system: { [] }))
            #expect(size.width > 0 && size.height > 0)
            #expect(reads == 0)
            #expect(ClipKit.instantiatedSingletons == singletons)

            _ = layOut(ShortcutsSettingsPage(
                windows: .fake(.off), clipboard: controller(isOn: true), clipboardChord: chord, keybinds: { [] }, system: { [] }))
            #expect(reads > 0)
        }

        /// "Delete Clipboard History…" shows on the History page while off, and only when history is saved.
        @Test func deleteHistoryHiddenWhenNoStore() throws {
            let home = FileManager.default.temporaryDirectory.appending(path: "mooring-clipboard-tests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: home) }
            let storeURL = home.appending(path: "Clipboard/Storage.sqlite")
            let clipboard = ClipboardController(
                settings: FakeClipboardSettings(enabled: false), storeURL: storeURL, makeKit: { _ in FakeClipKit() })
            #expect(!ClipboardSettingsPage.offersHistoryDeletion(page: .clipboardHistory, clipboard: clipboard))
            let size = layOut(ClipboardSettingsPage(page: .clipboardHistory, clipboard: clipboard, chooseApp: { nil }))
            #expect(size.width > 0 && size.height > 0)

            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            #expect(ClipboardSettingsPage.offersHistoryDeletion(page: .clipboardHistory, clipboard: clipboard))
            #expect(!ClipboardSettingsPage.offersHistoryDeletion(page: .clipboardAppearance, clipboard: clipboard))
            let withDelete = layOut(ClipboardSettingsPage(page: .clipboardHistory, clipboard: clipboard, chooseApp: { nil }))
            #expect(withDelete.height > size.height)

            clipboard.turnOn()
            #expect(!ClipboardSettingsPage.offersHistoryDeletion(page: .clipboardHistory, clipboard: clipboard))
            clipboard.turnOff()
            clipboard.deleteHistory()
            #expect(!ClipboardSettingsPage.offersHistoryDeletion(page: .clipboardHistory, clipboard: clipboard))

            #expect(ClipboardSettingsPage.deleteHistoryTitle == "Delete Clipboard History…")
            #expect(ClipboardSettingsPage.deleteHistoryQuestion == "Delete all saved clipboard history?")
            #expect(ClipboardSettingsPage.deleteHistoryWarning == "This can't be undone.")
            #expect(ClipboardSettingsPage.deleteTitle == "Delete")
        }

        @Test func clipboardToggleTurnsClipboardOnAndOff() {
            let clipboard = controller(isOn: false)
            let isOn = ClipboardToggle.isOn(clipboard)
            #expect(!isOn.wrappedValue)
            isOn.wrappedValue = true
            #expect(clipboard.isOn)
            #expect(isOn.wrappedValue)
            isOn.wrappedValue = false
            #expect(!clipboard.isOn)
            #expect(SettingsPage.clipboardHistory.hasClipboardToggle)
            #expect(!SettingsPage.clipboardAppearance.hasClipboardToggle)
        }

        private func layOut(_ view: some View) -> NSSize {
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            defer { window.close() }
            return host.fittingSize
        }
    }
}

@MainActor
struct ClipboardSettingsTests {
    @Test func clipboardGroupListsThreePages() {
        let pages = SettingsPage.allCases.filter { $0.group == "Clipboard" }
        #expect(pages == clipboardPages)
        #expect(pages.map(\.title) == ["History", "Ignore Rules", "Appearance"])
        #expect(pages.allSatisfy { $0.clipboardContent(isOn: false) != nil })
        #expect(SettingsPage.general.clipboardContent(isOn: true) == nil)
        #expect(SettingsPage.windowsBehavior.clipboardContent(isOn: false) == nil)
        let groups = SettingsPage.allCases.map(\.group).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        #expect(groups == ["General", "Awake", "Windows", "Clipboard", "Mooring"])
    }

    private func model(_ fake: FakeClipboardSettingsAccess) -> ClipboardSettingsModel {
        ClipboardSettingsModel(access: fake.access)
    }

    @Test func changesAreWrittenAndUnchangedValuesAreNot() {
        let fake = FakeClipboardSettingsAccess()
        let model = model(fake)
        model.binding(\.clearOnQuit).wrappedValue = false
        #expect(fake.writes.isEmpty)
        model.binding(\.clearOnQuit).wrappedValue = true
        model.binding(\.pasteByDefault).wrappedValue = true
        model.binding(\.removeFormattingByDefault).wrappedValue = true
        model.binding(\.recordUniversalClipboard).wrappedValue = true
        #expect(fake.values.clearOnQuit && fake.values.pasteByDefault)
        #expect(fake.values.removeFormattingByDefault && fake.values.recordUniversalClipboard)
        #expect(model.values == fake.values)
    }

    @Test func historySizeAndImageHeightStayInRange() {
        let fake = FakeClipboardSettingsAccess()
        let model = model(fake)
        model.binding(\.historySize).wrappedValue = 5
        #expect(fake.values.historySize == 10)
        model.binding(\.historySize).wrappedValue = 5000
        #expect(fake.values.historySize == 999)
        model.binding(\.historySize).wrappedValue = 321
        #expect(fake.values.historySize == 321)
        model.binding(\.imageMaxHeight).wrappedValue = 0
        #expect(fake.values.imageMaxHeight == 1)
        model.binding(\.imageMaxHeight).wrappedValue = 900
        #expect(fake.values.imageMaxHeight == 200)
        #expect(ClipboardSettingsModel.historySizeRange == 10...999)
    }

    @Test func appearanceChoicesAreWritten() {
        let fake = FakeClipboardSettingsAccess()
        let model = model(fake)
        model.binding(\.popupPosition).wrappedValue = .statusItem
        model.binding(\.pinsPosition).wrappedValue = .bottom
        model.binding(\.searchVisibility).wrappedValue = .never
        model.binding(\.showPreview).wrappedValue = false
        #expect(fake.values.popupPosition == .statusItem)
        #expect(fake.values.pinsPosition == .bottom)
        #expect(fake.values.searchVisibility == .never)
        #expect(!fake.values.showPreview)
    }

    /// The panel is injected: the chosen app's bundle id is stored once, and nothing is stored on cancel.
    @Test func addingAnIgnoredAppStoresItsBundleID() {
        let fake = FakeClipboardSettingsAccess()
        let model = model(fake)
        var asked = 0
        model.addIgnoredApp(choosing: { asked += 1; return "com.example.notes" })
        #expect(asked == 1)
        #expect(fake.values.ignoredApps == ["com.example.vault", "com.example.notes"])
        model.addIgnoredApp(choosing: { "com.example.notes" })
        #expect(fake.values.ignoredApps == ["com.example.vault", "com.example.notes"])
        let writes = fake.writes.count
        model.addIgnoredApp(choosing: { nil })
        #expect(fake.writes.count == writes)
        model.removeIgnoredApp("com.example.vault")
        #expect(fake.values.ignoredApps == ["com.example.notes"])
    }

    /// Maccy's "ignore all apps except listed" stays hidden: with the password-manager default list it
    /// would record only copies from password managers. No page names it and no edit changes it.
    @Test func ignoreAllAppsExceptListedIsNeverExposed() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let walker = FileManager.default.enumerator(at: root.appending(path: "Settings"), includingPropertiesForKeys: nil)
        let sources = (walker?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        #expect(sources.contains { $0.lastPathComponent == "ClipboardSettingsPages.swift" })
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("ignoreAllAppsExceptListed"), "\(file.lastPathComponent)")
            #expect(text.range(of: "except listed", options: .caseInsensitive) == nil, "\(file.lastPathComponent)")
        }

        let fake = FakeClipboardSettingsAccess()
        let model = model(fake)
        model.addIgnoredApp(choosing: { "com.example.notes" })
        model.removeIgnoredApp("com.example.vault")
        model.removeIgnoredApp("com.example.notes")
        model.addIgnoredType("com.example.other")
        model.removeIgnoredType("com.example.secret")
        model.addIgnoreRegex("^x")
        model.removeIgnoreRegex("^x")
        model.binding(\.recordUniversalClipboard).wrappedValue = true
        #expect(!fake.writes.isEmpty)
        #expect(fake.writes.allSatisfy { !$0.ignoreAllAppsExceptListed })
    }

    @Test func pickerPanelIsLimitedToAppsInApplications() {
        let panel = NSOpenPanel()
        IgnoredAppPicker.configure(panel)
        #expect(panel.allowedContentTypes == [UTType.applicationBundle])
        #expect(panel.directoryURL?.path(percentEncoded: false) == "/Applications")
        #expect(panel.canChooseFiles && !panel.canChooseDirectories)
        #expect(!panel.allowsMultipleSelection)
    }

    @Test func ignoredAppShowsItsNameAndFallsBackToTheBundleID() {
        #expect(IgnoredAppPicker.name(for: "com.apple.finder") == "Finder")
        #expect(IgnoredAppPicker.name(for: "com.example.not-installed") == "com.example.not-installed")
        #expect(IgnoredAppPicker.icon(for: "com.example.not-installed") == nil)
        #expect(IgnoredAppPicker.icon(for: "com.apple.finder") != nil)
    }

    @Test func ignoredTypesAreAddedSortedAndRemoved() {
        let fake = FakeClipboardSettingsAccess()
        let model = model(fake)
        model.addIgnoredType("  com.example.other ")
        model.addIgnoredType("")
        model.addIgnoredType("com.example.secret")
        #expect(fake.values.ignoredTypes == ["com.example.secret", "com.example.other"])
        #expect(model.sortedIgnoredTypes == ["com.example.other", "com.example.secret"])
        model.removeIgnoredType("com.example.secret")
        #expect(fake.values.ignoredTypes == ["com.example.other"])
    }

    @Test func ignoreRegexesRejectInvalidAndDuplicatePatterns() {
        let fake = FakeClipboardSettingsAccess()
        let model = model(fake)
        #expect(model.addIgnoreRegex("^secret") == true)
        #expect(model.addIgnoreRegex("([unclosed") == false)
        #expect(model.addIgnoreRegex("^secret") == true)
        #expect(model.addIgnoreRegex("  ") == true)
        #expect(fake.values.ignoreRegexes == ["^\\d{16}$", "^secret"])
        model.removeIgnoreRegex("^secret")
        #expect(fake.values.ignoreRegexes == ["^\\d{16}$"])
    }
}

@MainActor
struct SettingsPreferencesTests {
    /// The popup's "Preferences…" (⌘,) opens Settings on Clipboard → History.
    @Test func preferencesOpensClipboardHistory() {
        var presented: [NSWindow] = []
        let controller = SettingsWindowController(present: { presented.append($0) })
        #expect(controller.selectedPage == .general)
        controller.showClipboardHistory()
        #expect(controller.selectedPage == .clipboardHistory)
        #expect(presented.count == 1)
        #expect(SettingsPage.clipboardHistory.title == "History")
        #expect(SettingsPage.clipboardHistory.group == "Clipboard")
        presented.forEach { $0.close() }
    }
}

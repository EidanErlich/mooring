import AppKit
import SwiftUI
import Testing
@testable import Mooring

@MainActor
struct ShortcutConflictsTests {
    private let spotlight = SystemHotkey(name: "Spotlight", chord: "⌘␣", enabled: true)

    private func entry(_ title: String, _ chord: String?, owner: String = "Windows") -> ShortcutEntry {
        ShortcutEntry(owner: owner, title: title, chord: chord)
    }

    @Test func duplicateChordsFlagBoth() {
        let result = ShortcutConflicts.annotate(
            [entry("Left Half", "⌃⌥←"), entry("Maximize", "⌃⌥↑"), entry("Custom", "⌃⌥←")], system: [])
        #expect(result.map(\.warning) == ["Also used by Custom", nil, "Also used by Left Half"])
    }

    @Test func enabledSystemHotkeyFlags() {
        let result = ShortcutConflicts.annotate([entry("Spot", "⌘␣")], system: [spotlight])
        #expect(result.map(\.warning) == ["Used by macOS: Spotlight"])
    }

    @Test func disabledSystemHotkeyIgnored() {
        let off = SystemHotkey(name: "Spotlight", chord: "⌘␣", enabled: false)
        #expect(ShortcutConflicts.annotate([entry("Spot", "⌘␣")], system: [off]).map(\.warning) == [nil])
    }

    @Test func nilChordNeverConflicts() {
        let result = ShortcutConflicts.annotate([entry("A", nil), entry("B", nil)], system: [spotlight])
        #expect(result.map(\.warning) == [nil, nil])
    }

    /// WindowKit writes modifiers as it likes; the comparison uses ⌃⌥⇧⌘ order for both sides.
    @Test func chordsCompareAcrossModifierOrder() {
        let result = ShortcutConflicts.annotate(
            [entry("A", "⌘⌃B"), entry("B", "⌃⌘B"), entry("C", "⌃⌥⇧⌘A")],
            system: [SystemHotkey(name: "Thing", chord: "⌘⇧⌥⌃A", enabled: true)])
        #expect(result.map(\.warning) == ["Also used by B", "Also used by A", "Used by macOS: Thing"])
        #expect(ShortcutChord.normalize("⇪⌘⌃A") == "⌃⌘⇪A")
        #expect(ShortcutChord.format(modifiers: [.command, .control], key: "A") == "⌃⌘A")
    }

    @Test func windowsOffShowsNoChords() {
        var calls = 0
        let content = ShortcutsContent.make(windows: .off, keybinds: { calls += 1; return [] }, system: [spotlight])
        #expect(calls == 0)
        #expect(content.windows.isEmpty)
        #expect(content.windowsNote == "Windows is off: turn it on to use its shortcuts")
        #expect(content.awake == [ShortcutRow(title: "Toggle On/Off", chord: "None", warning: nil)])

        for state in [WindowsController.State.waitingForTrust, .needsAccessibility] {
            #expect(ShortcutsContent.make(windows: state, keybinds: { calls += 1; return [] }, system: []).windows.isEmpty)
        }
        #expect(calls == 0)

        let size = layOut(ShortcutsSettingsPage(windows: .fake(.off), keybinds: { calls += 1; return [] }, system: { [] }))
        #expect(size.width > 0 && size.height > 0)
        #expect(calls == 0)
    }

    @Test func windowsOnListsEveryKeybindAndFlagsConflicts() {
        let keybinds = [
            entry("Windows trigger key", "⇪"), entry("Left Half", "⌘␣"), entry("Maximize", "⌃⌥⌘M"), entry("Center", "⌃⌥⌘M")
        ]
        let content = ShortcutsContent.make(windows: .on, keybinds: { keybinds }, system: [spotlight])
        #expect(content.windowsNote == nil)
        #expect(content.windows.map(\.title) == ["Windows trigger key", "Left Half", "Maximize", "Center"])
        #expect(content.windows.map(\.chord) == ["⇪", "⌘␣", "⌃⌥⌘M", "⌃⌥⌘M"])
        #expect(content.windows.map(\.warning) == [nil, "Used by macOS: Spotlight", "Also used by Center", "Also used by Maximize"])
        #expect(content.awake.map(\.chord) == ["None"])

        let size = layOut(ShortcutsSettingsPage(windows: .fake(.on), keybinds: { keybinds }, system: { [self.spotlight] }))
        #expect(size.width > 0 && size.height > 0)
    }

    @Test func capsLockLinkPointsAtLoopsReadme() {
        #expect(ShortcutsSettingsPage.capsLockAdviceURL.absoluteString == "https://github.com/MrKai77/Loop#readme")
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

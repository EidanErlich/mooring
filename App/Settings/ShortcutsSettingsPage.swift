import ClipKit
import SwiftUI
import WindowKit

struct ShortcutRow: Equatable {
    let title: String
    let chord: String
    let warning: String?
}

/// What General → Shortcuts shows (docs/design/2026-10-03-stage-3a-windowkit-design.md,
/// "General → Shortcuts").
struct ShortcutsContent: Equatable {
    static let windowsOffNote = "Windows is off: turn it on to use its shortcuts"
    static let clipboardOffNote = "Clipboard is off: turn it on to use its shortcut"
    static let none = "None"

    let awake: [ShortcutRow]
    let windows: [ShortcutRow]
    /// Stands in for the Windows rows while Windows isn't on.
    let windowsNote: String?
    /// The Clipboard popup's row while Clipboard is on.
    let clipboard: [ShortcutRow]
    /// Stands in for the Clipboard row while Clipboard is off.
    let clipboardNote: String?

    /// `keybinds` is called only while Windows is on, so WindowKit is never touched while it's off.
    /// `clipboardChord` is nil while Clipboard is off; otherwise it reads the popup hotkey (nil when it has none).
    @MainActor
    static func make(windows state: WindowsController.State, clipboardChord: (@MainActor () -> String?)? = nil,
                     keybinds: @MainActor () -> [ShortcutEntry], system: [SystemHotkey]) -> ShortcutsContent {
        let awake = [ShortcutEntry(owner: "Awake", title: "Toggle On/Off", chord: nil)]
        let windows = state == .on ? keybinds() : []
        let clipboard = clipboardChord.map { [ShortcutEntry(owner: "Clipboard", title: "Clipboard popup", chord: $0())] } ?? []
        let annotated = ShortcutConflicts.annotate(awake + windows + clipboard, system: system).map {
            ShortcutRow(title: $0.title, chord: $0.chord ?? none, warning: $1)
        }
        return ShortcutsContent(
            awake: Array(annotated.prefix(awake.count)),
            windows: Array(annotated.dropFirst(awake.count).prefix(windows.count)),
            windowsNote: state == .on ? nil : windowsOffNote,
            clipboard: Array(annotated.suffix(clipboard.count)),
            clipboardNote: clipboardChord == nil ? clipboardOffNote : nil)
    }

    /// The popup hotkey as a chord in `ShortcutChord`'s format, so it compares exactly with the others.
    @MainActor
    static func chord(of shortcut: KeyboardShortcuts.Shortcut?) -> String? {
        shortcut.map { ShortcutChord.normalize($0.description) }
    }

    /// Reading the hotkey creates its `KeyboardShortcuts.Name`, so this runs only while Clipboard is on.
    @MainActor
    static func clipboardPopupChord() -> String? {
        chord(of: KeyboardShortcuts.getShortcut(for: ClipKit.popupShortcutName))
    }

    /// WindowKit's trigger key and keybinds, with the trigger row named as the page names it.
    @MainActor
    static func windowKitKeybinds() -> [ShortcutEntry] {
        WindowKit.keybinds().map {
            ShortcutEntry(owner: "Windows", title: $0.title == "Trigger Key" ? "Windows trigger key" : $0.title, chord: $0.chord)
        }
    }
}

/// General → Shortcuts: every global shortcut Mooring has, with conflicts flagged. Nothing is edited here.
struct ShortcutsSettingsPage: View {
    static let capsLockAdviceURL = URL(string: "https://github.com/MrKai77/Loop#readme")! // swiftlint:disable:this force_unwrapping

    let windows: WindowsController?
    var clipboard: ClipboardController?
    var clipboardChord: @MainActor () -> String? = ShortcutsContent.clipboardPopupChord
    var keybinds: @MainActor () -> [ShortcutEntry] = ShortcutsContent.windowKitKeybinds
    var system: () -> [SystemHotkey] = SystemHotkeys.readSystem
    @State private var systemHotkeys: [SystemHotkey]?
    @State private var windowsKeybinds: [ShortcutEntry]?

    var body: some View {
        let content = ShortcutsContent.make(
            windows: windows?.state ?? .off, clipboardChord: clipboard?.isOn == true ? clipboardChord : nil,
            keybinds: { windowsKeybinds ?? keybinds() }, system: systemHotkeys ?? [])
        Form {
            Section("Awake") { rows(content.awake) }
            Section("Windows") {
                if let note = content.windowsNote {
                    Text(note).foregroundStyle(.secondary)
                } else {
                    rows(content.windows)
                }
            }
            Section("Clipboard") {
                if let note = content.clipboardNote {
                    Text(note).foregroundStyle(.secondary)
                } else {
                    rows(content.clipboard)
                }
            }
            Section {
                Link("Using Caps Lock as the trigger key (Loop's README)", destination: Self.capsLockAdviceURL)
                Text("Shortcuts are edited where they live: Windows → Keybinds, Clipboard → History, and Awake for the on/off shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onChange(of: windows?.state) { refresh() }
        .navigationTitle("Shortcuts")
    }

    /// Re-reads both sources, so edits made on the Keybinds page show. WindowKit is read only while Windows is on.
    private func refresh() {
        systemHotkeys = system()
        windowsKeybinds = windows?.state == .on ? keybinds() : nil
    }

    private func rows(_ rows: [ShortcutRow]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent(row.title) {
                    Text(row.chord).font(.system(.body, design: .monospaced))
                }
                if let warning = row.warning {
                    Text("⚠ \(warning)").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}

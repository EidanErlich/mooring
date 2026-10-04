import SwiftUI
import WindowKit

struct ShortcutRow: Equatable {
    let title: String
    let chord: String
    let warning: String?
}

/// What General → Shortcuts shows (docs/superpowers/specs/2026-10-03-stage-3a-windowkit-design.md,
/// "General → Shortcuts").
struct ShortcutsContent: Equatable {
    static let windowsOffNote = "Windows is off: turn it on to use its shortcuts"
    static let none = "None"

    let awake: [ShortcutRow]
    let windows: [ShortcutRow]
    /// Stands in for the Windows rows while Windows isn't on.
    let windowsNote: String?

    /// `keybinds` is called only while Windows is on, so WindowKit is never touched while it's off.
    @MainActor
    static func make(windows state: WindowsController.State, keybinds: @MainActor () -> [ShortcutEntry],
                     system: [SystemHotkey]) -> ShortcutsContent {
        let awake = [ShortcutEntry(owner: "Awake", title: "Toggle On/Off", chord: nil)]
        let windows = state == .on ? keybinds() : []
        let annotated = ShortcutConflicts.annotate(awake + windows, system: system).map {
            ShortcutRow(title: $0.title, chord: $0.chord ?? none, warning: $1)
        }
        return ShortcutsContent(awake: Array(annotated.prefix(awake.count)), windows: Array(annotated.dropFirst(awake.count)),
                                windowsNote: state == .on ? nil : windowsOffNote)
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
    var keybinds: @MainActor () -> [ShortcutEntry] = ShortcutsContent.windowKitKeybinds
    var system: () -> [SystemHotkey] = SystemHotkeys.readSystem
    @State private var systemHotkeys: [SystemHotkey]?

    var body: some View {
        let content = ShortcutsContent.make(windows: windows?.state ?? .off, keybinds: keybinds, system: systemHotkeys ?? [])
        Form {
            Section("Awake") { rows(content.awake) }
            Section("Windows") {
                if let note = content.windowsNote {
                    Text(note).foregroundStyle(.secondary)
                } else {
                    rows(content.windows)
                }
            }
            Section {
                Link("Using Caps Lock as the trigger key (Loop's README)", destination: Self.capsLockAdviceURL)
                Text("Shortcuts are edited where they live: Windows → Keybinds, and Awake for the on/off shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { systemHotkeys = system() }
        .navigationTitle("Shortcuts")
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

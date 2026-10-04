import AppKit

/// One global shortcut Mooring lists. `chord` is nil when none is set.
struct ShortcutEntry: Equatable {
    let owner: String
    let title: String
    let chord: String?
}

/// A macOS symbolic hotkey, with its chord already in `ShortcutChord` form.
struct SystemHotkey: Equatable {
    let name: String
    let chord: String
    let enabled: Bool
}

/// The one chord format both WindowKit's and macOS's shortcuts go through: modifiers in ⌃⌥⇧⌘ order, then the key.
enum ShortcutChord {
    private static let modifiers: [(symbol: Character, flag: NSEvent.ModifierFlags)] = [
        ("⌃", .control), ("⌥", .option), ("⇧", .shift), ("⌘", .command)
    ]

    static func format(modifiers flags: NSEvent.ModifierFlags, key: String) -> String {
        String(modifiers.filter { flags.contains($0.flag) }.map(\.symbol)) + key
    }

    /// Reorders the modifiers of an already-written chord; everything else keeps its order.
    static func normalize(_ chord: String) -> String {
        let symbols = Set(modifiers.map(\.symbol))
        let present = modifiers.filter { chord.contains($0.symbol) }.map(\.symbol)
        return String(present) + chord.filter { !symbols.contains($0) }
    }
}

enum ShortcutConflicts {
    /// Each entry with its warning: "Also used by <other>" for a chord Mooring uses twice, and
    /// "Used by macOS: <name>" for an enabled system shortcut on the same chord.
    static func annotate(_ entries: [ShortcutEntry], system: [SystemHotkey]) -> [(ShortcutEntry, warning: String?)] {
        let chords = entries.map { $0.chord.map(ShortcutChord.normalize) }
        let enabled = system.filter(\.enabled)
        return entries.enumerated().map { index, entry in
            guard let chord = chords[index] else { return (entry, nil) }
            let others = entries.indices.filter { $0 != index && chords[$0] == chord }.map { entries[$0].title }
            var warnings = others.map { "Also used by \($0)" }
            if let match = enabled.first(where: { ShortcutChord.normalize($0.chord) == chord }) {
                warnings.append("Used by macOS: \(match.name)")
            }
            return (entry, warnings.isEmpty ? nil : warnings.joined(separator: "; "))
        }
    }
}

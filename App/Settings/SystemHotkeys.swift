import AppKit

/// The macOS symbolic hotkeys (`AppleSymbolicHotKeys` in `com.apple.symbolichotkeys`).
enum SystemHotkeys {
    static let domain = "com.apple.symbolichotkeys"
    static let key = "AppleSymbolicHotKeys"
    private static let noKey = 65535

    /// Reads the real preferences. An unreadable domain gives no hotkeys; a missing one is a stock Mac.
    static func readSystem() -> [SystemHotkey] {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else { return read(from: [:]) }
        return read(from: [key: value])
    }

    /// macOS writes an entry only after a shortcut is changed, so the stock chords of the named ids are
    /// used when an id is absent, or present and enabled without a `value`. `enabled == false` turns
    /// a default off; a `value` always wins. Entries of the wrong shape are skipped.
    static func read(from domain: [String: Any]) -> [SystemHotkey] {
        let entries: [String: Any]
        if let present = domain[key] {
            guard let dictionary = present as? [String: Any] else { return [] }
            entries = dictionary
        } else {
            entries = [:]
        }
        let ids = Set(entries.keys).union(defaults.keys.map(String.init))
        return ids.sorted { (Int($0) ?? 0, $0) < (Int($1) ?? 0, $1) }.compactMap { id in
            let number = Int(id) ?? -1
            guard let raw = entries[id] else { return stock(number) }
            guard let entry = raw as? [String: Any] else { return nil }
            let enabled = entry["enabled"] as? Bool ?? false
            guard let value = entry["value"] as? [String: Any] else { return enabled ? stock(number) : nil }
            guard let parameters = value["parameters"] as? [Int], parameters.count >= 3,
                  let label = keyLabel(ascii: parameters[0], code: parameters[1]) else { return nil }
            let chord = ShortcutChord.format(modifiers: NSEvent.ModifierFlags(rawValue: UInt(parameters[2])), key: label)
            return SystemHotkey(name: name(forID: number), chord: chord, enabled: enabled)
        }
    }

    private static func stock(_ id: Int) -> SystemHotkey? {
        defaults[id].map { SystemHotkey(name: name(forID: id), chord: $0, enabled: true) }
    }

    private static let defaults: [Int: String] = [
        64: "⌘␣", 65: "⌥⌘␣", 32: "⌃↑", 33: "⌃↓", 36: "F11", 60: "⌃␣", 61: "⌃⌥␣",
        28: "⇧⌘3", 29: "⌃⇧⌘3", 30: "⇧⌘4", 31: "⌃⇧⌘4", 184: "⇧⌘5"
    ]

    static func name(forID id: Int) -> String {
        switch id {
        case 64: "Spotlight"
        case 32: "Mission Control"
        case 36: "Show Desktop"
        case 60: "Select the previous input source"
        case 61: "Select next source in Input menu"
        case 28...31: "Screenshot"
        case 33: "Application windows"
        case 65: "Finder search window"
        case 184: "Screenshot and recording"
        default: "a macOS shortcut"
        }
    }

    /// The key as WindowKit writes it: symbols for the non-printing keys, otherwise the uppercased character.
    private static func keyLabel(ascii: Int, code: Int) -> String? {
        if let special = specialKeys[code] { return special }
        if (33...126).contains(ascii), let scalar = Unicode.Scalar(ascii) {
            return String(Character(scalar)).uppercased()
        }
        return code == noKey ? nil : "Key \(code)"
    }

    private static let specialKeys: [Int: String] = [
        36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20"
    ]
}

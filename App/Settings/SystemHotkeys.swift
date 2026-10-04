import AppKit

/// The macOS symbolic hotkeys (`AppleSymbolicHotKeys` in `com.apple.symbolichotkeys`).
enum SystemHotkeys {
    static let domain = "com.apple.symbolichotkeys"
    static let key = "AppleSymbolicHotKeys"
    private static let noKey = 65535

    /// Reads the real preferences; an unreadable domain gives no hotkeys.
    static func readSystem() -> [SystemHotkey] {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else { return [] }
        return read(from: [key: value])
    }

    /// Parses a `com.apple.symbolichotkeys` dictionary. Entries that don't have the expected shape are skipped.
    static func read(from domain: [String: Any]) -> [SystemHotkey] {
        guard let entries = domain[key] as? [String: Any] else { return [] }
        return entries.keys.sorted { (Int($0) ?? 0, $0) < (Int($1) ?? 0, $1) }.compactMap { id in
            guard let entry = entries[id] as? [String: Any],
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Int], parameters.count >= 3,
                  let label = keyLabel(ascii: parameters[0], code: parameters[1]) else { return nil }
            let chord = ShortcutChord.format(modifiers: NSEvent.ModifierFlags(rawValue: UInt(parameters[2])), key: label)
            return SystemHotkey(name: name(forID: Int(id) ?? -1), chord: chord, enabled: entry["enabled"] as? Bool ?? false)
        }
    }

    static func name(forID id: Int) -> String {
        switch id {
        case 64: "Spotlight"
        case 32: "Mission Control"
        case 36: "Show Desktop"
        case 60: "Select the previous input source"
        case 61: "Select next source in Input menu"
        case 28...31: "Screenshot"
        case 33: "Application windows"
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

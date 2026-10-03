import CoreGraphics

/// One way to write a key chord, shared by Loop's keybinds and the Shortcuts page:
/// modifiers as fn ⇪ ⌃ ⌥ ⇧ ⌘ (left and right alike), then the other keys in key-code order.
public enum WindowChord {
    private static let modifierOrder: [(key: CGKeyCode, symbol: String)] = [
        (.kVK_Function, "fn"),
        (.kVK_CapsLock, "⇪"),
        (.kVK_Control, "⌃"),
        (.kVK_Option, "⌥"),
        (.kVK_Shift, "⇧"),
        (.kVK_Command, "⌘")
    ]

    public static func format(_ keyCodes: Set<UInt16>) -> String {
        let keys = Set(keyCodes.map(\.baseModifier))
        let modifiers = modifierOrder.filter { keys.contains($0.key) }.map(\.symbol)
        let others = keys.filter { !$0.isModifier }.sorted().map(name)
        return (modifiers + others).joined()
    }

    private static func name(_ key: CGKeyCode) -> String {
        key.humanReadable?.uppercased() ?? "Key \(key)"
    }
}

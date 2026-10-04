import Foundation
import KeyboardShortcuts

/// The one place Maccy's hotkeys are registered and unregistered, so none is held system-wide while
/// it shouldn't be.
///
/// KeyboardShortcuts registers a name's default shortcut the moment the name is first created, and
/// again whenever the user records a new one. Maccy only ever uses the popup hotkey globally; its pin,
/// delete and preview shortcuts are read as key equivalents inside the popup (Maccy's AppDelegate
/// disabled them at launch for the same reason).
enum ClipKitShortcuts {
    /// True while a ClipKit runs; the popup hotkey may be registered only then.
    static var popupActive = false

    static let popupRawValue = "clipboardPopup"

    /// The names this enum last registered and hasn't unregistered since.
    private(set) static var registered: Set<KeyboardShortcuts.Name> = []

    /// Unregisters a name's shortcut system-wide. Tests swap it to watch the calls.
    static var unregister: (KeyboardShortcuts.Name) -> Void = { KeyboardShortcuts.disable($0) }

    /// Registers `name` if it may be registered now; otherwise makes sure it isn't.
    static func enable(_ name: KeyboardShortcuts.Name) {
        guard name == .popup, popupActive else {
            disable(name)
            return
        }
        KeyboardShortcuts.enable(name)
        registered.insert(name)
    }

    static func disable(_ name: KeyboardShortcuts.Name) {
        registered.remove(name)
        // Unregistering is by key combination, so it would also take down a running popup hotkey
        // the user gave the same keys.
        if name.rawValue != popupRawValue, sharesTheRegisteredPopupKeys(name) {
            return
        }
        unregister(name)
    }

    private static func sharesTheRegisteredPopupKeys(_ name: KeyboardShortcuts.Name) -> Bool {
        guard registered.contains(.popup), let keys = KeyboardShortcuts.getShortcut(for: name) else { return false }
        return keys == KeyboardShortcuts.getShortcut(for: .popup)
    }

    /// Unregisters `name` now and after every change while `isActive` is false.
    static func guarded(
        _ name: KeyboardShortcuts.Name,
        registeredWhile isActive: @escaping () -> Bool = { false }
    ) -> KeyboardShortcuts.Name {
        if !isActive() {
            disable(name)
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
            object: nil,
            queue: nil
        ) { notification in
            guard let changed = notification.userInfo?["name"] as? KeyboardShortcuts.Name,
                  changed == name, !isActive() else { return }
            disable(name)
        }
        return name
    }
}

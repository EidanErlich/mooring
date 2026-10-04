import AwakeKit
import Defaults

extension AwakeSettings: @retroactive Defaults.Serializable {}

extension Defaults.Keys {
    /// Everything the awake engine reads from Settings, stored as one Codable value.
    static let awake = Key<AwakeSettings>("awake", default: AwakeSettings())
    /// Settings → General: left click opens the dropdown, right click toggles.
    static let swapClickActions = Key<Bool>("swapClickActions", default: false)
    /// Settings → Windows: the window manager. Off until turned on; stays true while Accessibility is revoked.
    static let windowsEnabled = Key<Bool>("windowsEnabled", default: false)
    /// Settings → Clipboard: the clipboard history. Off until turned on.
    static let clipboardEnabled = Key<Bool>("clipboardEnabled", default: false)
    /// Settings → General: post a notification when a guardrail pauses awake.
    static let notifyGuardrails = Key<Bool>("notifyGuardrails", default: true)
    /// Settings → General: show the countdown ("1:12", "42m") in the menu-bar pill.
    static let showTimeLeftInMenuBar = Key<Bool>("showTimeLeftInMenuBar", default: true)
    /// Settings → Advanced: Sparkle checks for updates on its own. Off until the user agrees.
    static let checkForUpdates = Key<Bool>("checkForUpdates", default: false)
    /// The update consent alert has been answered, so it isn't shown again.
    static let didAskForUpdates = Key<Bool>("didAskForUpdates", default: false)
}

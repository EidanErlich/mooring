import AppKit
import AwakeKit
import Defaults

/// The one-time confirmation before lid mode runs on battery (docs/SPEC.md 1.7,
/// "Lid mode on battery"). Until the user allows it, lid mode applies only on AC.
enum LidOptIn {
    static func needsConfirmation(power: PowerSnapshot, settings: AwakeSettings) -> Bool {
        !power.onAC && power.batteryPercent != nil && !settings.allowLidOnBattery
    }

    /// Shows the sheet; true means "Allow on battery", which is remembered.
    @MainActor
    static func confirm() -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Keep your Mac awake with the lid closed on battery?"
        alert.informativeText = "Lid mode on battery drains the battery and can make the Mac warm. "
            + "Keep it out of bags and sleeves while it runs. Mooring pauses lid mode below 20% battery."
        alert.addButton(withTitle: "Allow on battery")
        alert.addButton(withTitle: "Only on AC")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        Defaults[.awake].allowLidOnBattery = true
        return true
    }
}

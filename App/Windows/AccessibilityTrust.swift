import AppKit
import ApplicationServices

/// Whether macOS lets Mooring control other apps' windows. Only the Turn On flow and an
/// already-enabled Windows ever ask.
@MainActor
protocol AccessibilityTrust {
    func isTrusted() -> Bool
    func openSettingsPane()
    /// Asks macOS to add Mooring to the Accessibility list. Only on Turn On, never at launch or while polling.
    func requestListing()
}

struct LiveAccessibilityTrust: AccessibilityTrust {
    static let paneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Checks without prompting; the sheet explains instead of the system alert.
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func openSettingsPane() {
        NSWorkspace.shared.open(Self.paneURL)
    }

    /// macOS lists an app under Accessibility only once it has asked; the prompt option is that ask.
    /// The key is `kAXTrustedCheckOptionPrompt`'s value: Swift 6 rejects reading that C global.
    func requestListing() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

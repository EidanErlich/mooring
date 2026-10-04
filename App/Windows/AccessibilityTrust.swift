import AppKit
import ApplicationServices

/// Whether macOS lets Mooring control other apps' windows. Only the Turn On flow and an
/// already-enabled Windows ever ask.
@MainActor
protocol AccessibilityTrust {
    func isTrusted() -> Bool
    func openSettingsPane()
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
}

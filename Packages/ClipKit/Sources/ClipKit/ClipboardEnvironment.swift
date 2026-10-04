import AppKit
import Carbon.HIToolbox

/// What `Clipboard` reads from outside: the pasteboard it polls, the app a copy came from, whether
/// Secure Keyboard Entry is on, and whether Mooring has Accessibility. Tests inject all four.
struct ClipboardEnvironment {
    var pasteboard: NSPasteboard
    var sourceApplication: () -> (any SourceApplication)?
    var secureInputEnabled: () -> Bool
    var accessibilityTrusted: () -> Bool

    /// The real clipboard and probes.
    static var live: Self {
        Self(
            pasteboard: .general,
            sourceApplication: { NSWorkspace.shared.frontmostApplication },
            secureInputEnabled: { IsSecureEventInputEnabled() },
            accessibilityTrusted: { AXIsProcessTrusted() }
        )
    }

    /// Under a test host: a private pasteboard, no frontmost app, no Secure Keyboard Entry and no
    /// Accessibility, so no test reads or writes the real clipboard or posts ⌘V.
    static var testHost: Self {
        Self(
            pasteboard: NSPasteboard(name: .init("dev.mooring.clipkit.tests.default")),
            sourceApplication: { nil },
            secureInputEnabled: { false },
            accessibilityTrusted: { false }
        )
    }

    static var `default`: Self { TestHost.isActive ? testHost : live }
}

/// The parts of `NSRunningApplication` that `Clipboard` uses.
protocol SourceApplication {
    var bundleIdentifier: String? { get }
    var bundleURL: URL? { get }
    var localizedName: String? { get }
}

extension NSRunningApplication: SourceApplication {}

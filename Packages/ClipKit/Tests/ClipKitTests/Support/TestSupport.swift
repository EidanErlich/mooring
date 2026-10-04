import AppKit
import Defaults
import Foundation
import Testing
@testable import ClipKit

/// Tests that touch ClipKit's process-wide state (Maccy's singletons, the settings suite, the
/// popup hotkey) nest in here so they never run in parallel with each other.
@Suite(.serialized, .generalPasteboardUnchanged)
@MainActor
struct ClipKitGlobalStateTests {}

/// A uniquely named pasteboard standing in for the clipboard. Call `release()` when done.
@MainActor
final class TestPasteboard {
    let pasteboard = NSPasteboard(name: .init("dev.mooring.clipkit.tests.\(UUID().uuidString)"))

    func write(_ types: [NSPasteboard.PasteboardType: Data]) {
        let item = NSPasteboardItem()
        for (type, data) in types {
            item.setData(data, forType: type)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    func write(string: String, markedAs markers: [NSPasteboard.PasteboardType] = []) {
        var types: [NSPasteboard.PasteboardType: Data] = [.string: Data(string.utf8)]
        for marker in markers {
            types[marker] = Data()
        }
        write(types)
    }

    func release() {
        pasteboard.releaseGlobally()
    }
}

struct FakeApp: SourceApplication {
    var bundleIdentifier: String?
    var bundleURL: URL?
    var localizedName: String?
}

@MainActor
enum Fixture {
    /// An in-memory ClipKit polling `pasteboard`, with every outside probe injected.
    static func kit(
        pasteboard: TestPasteboard,
        sourceApp: @escaping () -> String? = { nil },
        secureInput: @escaping () -> Bool = { false },
        trusted: @escaping () -> Bool = { false }
    ) -> ClipKit {
        ClipKit(
            storeURL: nil,
            inMemory: true,
            environment: environment(pasteboard, sourceApp: sourceApp, secureInput: secureInput, trusted: trusted)
        )
    }

    static func environment(
        _ pasteboard: TestPasteboard,
        sourceApp: @escaping () -> String? = { nil },
        secureInput: @escaping () -> Bool = { false },
        trusted: @escaping () -> Bool = { false }
    ) -> ClipboardEnvironment {
        ClipboardEnvironment(
            pasteboard: pasteboard.pasteboard,
            sourceApplication: { sourceApp().map { FakeApp(bundleIdentifier: $0) } },
            secureInputEnabled: secureInput,
            accessibilityTrusted: trusted
        )
    }

    /// Clears the scratch settings suite and parks the popup hotkey on a combination nobody uses,
    /// so a test that starts ClipKit never holds ⇧⌘C.
    static func resetSettings() {
        Defaults.removeAll(suite: .clipKit)
        KeyboardShortcutsFixture.parkPopupShortcut()
    }

    /// Starts `kit` with an empty history.
    static func start(_ kit: ClipKit) {
        resetSettings()
        kit.start()
        kit.clear(all: true)
    }

    /// Records whatever is on the pasteboard now, as the polling timer would.
    static func poll() {
        Clipboard.shared.checkForChangesInPasteboard()
    }

    static func recordedTitles() -> [String] {
        History.shared.all.map(\.item.title)
    }

    static func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "dev.mooring.clipkit.tests.\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

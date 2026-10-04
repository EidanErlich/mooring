import AppKit
import Foundation
import Testing
@testable import WindowKit

extension WindowKitGlobalStateTests {
    /// Stash and focus switching stay hidden in 3a: not offered anywhere, and inert if a binding asks for them.
    @Suite
    @MainActor
    struct HiddenFeaturesTests {
        private let hiddenDirections: [WindowDirection] = [.stash, .unstash] + WindowDirection.focus

        @Test func stashAndFocusActionsAreNotOffered() {
            let picker = PickerSection<WindowDirection>.windowDirections
            let offered = picker.flatMap(\.items)
            #expect(!offered.isEmpty)
            for direction in hiddenDirections {
                #expect(!offered.contains(direction))
            }
            #expect(!picker.map(\.title).contains("Stash"))
            #expect(!picker.map(\.title).contains("Focus"))
        }

        @Test func stashActionIsANoOp() async {
            // A fresh process, so creating Loop's StashManager would show up in the singleton count.
            await #expect(processExitsWith: .success) {
                let engine = WindowActionEngine.shared
                let before = WindowKit.instantiatedSingletons
                let context = ResizeContext(screen: NSScreen.screens.first, action: WindowAction(.stash))
                let result = try? await engine.apply(context: context)
                let untouched = WindowKit.instantiatedSingletons == before && result?.success == true
                exit(untouched ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        /// Loop's app-level toggles (read by nothing in Mooring) and the jump to Loop's own Radial Menu
        /// tab are gone from the pages Mooring hosts. Checked in the sources, where they would be bound.
        @Test func behaviorHidesLoopAppControls() throws {
            let settingsWindow = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Sources/WindowKit/Loop/Settings Window")
            let files = try #require(FileManager.default.enumerator(at: settingsWindow, includingPropertiesForKeys: nil))
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            #expect(files.count > 10)
            let sources = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
            for hidden in ["$launchAtLogin", "$startHidden", "$hideMenuBarIcon", "\"Launch at login\"", "\"Start hidden\"",
                           "\"Hide menu bar icon\"", "windowModel.currentTab"] {
                #expect(!sources.contains(hidden), "\(hidden)")
            }
        }

        @Test func focusActionsFindNoTarget() async {
            for direction in WindowDirection.focus {
                let target = await WindowActionEngine.shared.resolveFocusTarget(WindowAction(direction), currentWindow: nil)
                #expect(target == nil)
            }
        }
    }
}

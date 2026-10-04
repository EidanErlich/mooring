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

        @Test func focusActionsFindNoTarget() async {
            for direction in WindowDirection.focus {
                let target = await WindowActionEngine.shared.resolveFocusTarget(WindowAction(direction), currentWindow: nil)
                #expect(target == nil)
            }
        }
    }
}

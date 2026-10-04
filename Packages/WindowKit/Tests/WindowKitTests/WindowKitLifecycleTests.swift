import AppKit
import Defaults
import Foundation
import Testing
@testable import WindowKit

/// Tests that touch WindowKit's process-wide state (Loop's singletons, the active capabilities)
/// nest in here so they never run in parallel with each other.
@Suite(.serialized)
@MainActor
struct WindowKitGlobalStateTests {}

extension WindowKitGlobalStateTests {
    @Suite
    @MainActor
    struct WindowKitLifecycleTests {
        @Test func startIsIdempotent() async {
            let kit = WindowKit()
            kit.start()
            kit.start()
            #expect(kit.isRunning)
            #expect(WindowKit.instantiatedSingletons > 0)

            // LoopManager and WindowDragManager each hold one Accessibility stream while running.
            #expect(await settledStreamCount(expecting: 2) == 2)

            kit.stop()
            #expect(!kit.isRunning)
            #expect(await settledStreamCount(expecting: 0) == 0)
            kit.stop()

            kit.start()
            #expect(await settledStreamCount(expecting: 2) == 2)
            kit.stop()
            #expect(await settledStreamCount(expecting: 0) == 0)
        }

        @Test func stopClosesIndicators() async throws {
            _ = NSApplication.shared
            let screen = try #require(NSScreen.screens.first)
            resetScratchWindowsSuite()
            defer { resetScratchWindowsSuite() }
            Defaults[.radialMenuVisibility] = true
            Defaults[.previewVisibility] = true

            let kit = WindowKit()
            kit.start()
            let context = ResizeContext(screen: screen, action: WindowAction(.leftHalf))
            LoopManager.shared.indicatorService.openAndUpdate(context: context, hideOnNoSelection: false)
            #expect(visibleWindowKitPanels() >= 2)

            kit.stop()
            #expect(visibleWindowKitPanels() == 0)
        }

        @Test func noSingletonsBeforeStart() async {
            await #expect(processExitsWith: .success) {
                let created = await MainActor.run {
                    _ = WindowKit.menuActions(primary: true)
                    _ = WindowKit.menuActions(primary: false)
                    _ = WindowKit.keybinds()
                    return WindowKit.instantiatedSingletons
                }
                exit(created == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        private func visibleWindowKitPanels() -> Int {
            NSApplication.shared.windows.filter { $0 is ActivePanel && $0.isVisible }.count
        }

        /// Waits for the stream count to reach `expecting`, then a little longer, so a second set of
        /// observers arriving late would still be counted.
        private func settledStreamCount(expecting: Int) async -> Int {
            for _ in 0..<200 where AccessibilityManager.shared.activeStreamCount != expecting {
                try? await Task.sleep(for: .milliseconds(10))
            }
            try? await Task.sleep(for: .milliseconds(200))
            return AccessibilityManager.shared.activeStreamCount
        }
    }
}

import AppKit
import SwiftUI
import Testing
import WindowKit
@testable import Mooring

/// Tests that read WindowKit's process-wide singleton count, or create Loop's singletons, nest in
/// here so they never run in parallel with each other.
@Suite(.serialized)
@MainActor
struct WindowKitGlobalStateTests {}

extension WindowsController {
    /// A real controller over fakes, brought to `state`. Its trust is granted unless `state` says otherwise.
    static func fake(_ state: State) -> WindowsController {
        let controller = WindowsController(
            trust: FakeTrust(trusted: state == .off || state == .on), makeRuntime: { FakeRuntime() },
            settings: FakeSettings(enabled: state == .on || state == .needsAccessibility), clock: FakeClock())
        if state == .waitingForTrust {
            controller.turnOn()
        } else {
            controller.launch()
        }
        #expect(controller.state == state)
        return controller
    }
}

extension WindowKitGlobalStateTests {
    @Suite
    @MainActor
    struct WindowsSettingsPageTests {
        private let windowsPages = SettingsPage.allCases.filter { $0.windowSettingsPage != nil }

        @Test func offPagesBuildNoWindowKit() {
            let before = WindowKit.instantiatedSingletons
            for state in [WindowsController.State.off, .waitingForTrust, .needsAccessibility] {
                let windows = WindowsController.fake(state)
                for page in windowsPages {
                    let size = layOut(WindowsSettingsPage(page: page, windows: windows))
                    #expect(size.width > 0 && size.height > 0, "\(page) while \(state)")
                }
            }
            #expect(WindowKit.instantiatedSingletons == before)
        }

        /// Loop's Luminare pages lay out in Mooring's detail area. Building them creates Loop's singletons.
        @Test func onPagesLayOutLoopsPages() {
            let before = WindowKit.instantiatedSingletons
            let windows = WindowsController.fake(.on)
            for page in windowsPages {
                let size = layOut(WindowsSettingsPage(page: page, windows: windows))
                #expect(size.width > 0 && size.height > 0, "\(page)")
            }
            // Laying out evaluated the bodies, so the off test above would have seen a Loop page built.
            #expect(WindowKit.instantiatedSingletons > before)

            for page in WindowSettingsPage.allCases {
                let size = layOut(WindowSettingsPage.view(page))
                #expect(size.width > 0 && size.height > 0, "\(page)")
            }
        }

        /// Lays `view` out at the Settings detail area's size in an offscreen window; returns its fitting size.
        private func layOut(_ view: some View) -> NSSize {
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            defer { window.close() }
            return host.fittingSize
        }
    }
}

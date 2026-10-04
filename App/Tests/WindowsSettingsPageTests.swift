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

        /// Off means off: no page asks for Loop's page while Windows isn't on. The singleton count is a second check.
        @Test func offPagesBuildNoWindowKit() {
            let before = WindowKit.instantiatedSingletons
            let builder = CountingBuilder()
            for state in [WindowsController.State.off, .waitingForTrust, .needsAccessibility] {
                let windows = WindowsController.fake(state)
                for page in windowsPages {
                    let size = layOut(WindowsSettingsPage(page: page, windows: windows, loopPage: builder.build))
                    #expect(size.width > 0 && size.height > 0, "\(page) while \(state)")
                }
            }
            #expect(builder.built.isEmpty)
            #expect(WindowKit.instantiatedSingletons == before)
        }

        /// Loop's Luminare pages lay out in Mooring's detail area. Building them creates Loop's singletons.
        @Test func onPagesLayOutLoopsPages() {
            let builder = CountingBuilder()
            let windows = WindowsController.fake(.on)
            for page in windowsPages {
                let size = layOut(WindowsSettingsPage(page: page, windows: windows, loopPage: builder.build))
                #expect(size.width > 0 && size.height > 0, "\(page)")
            }
            #expect(Set(builder.built) == Set(WindowSettingsPage.allCases))
            #expect(WindowKit.instantiatedSingletons > 0)

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

/// Builds Loop's real page, recording which pages were asked for.
@MainActor
private final class CountingBuilder {
    private(set) var built: [WindowSettingsPage] = []

    func build(_ page: WindowSettingsPage) -> AnyView {
        built.append(page)
        return WindowSettingsPage.view(page)
    }
}

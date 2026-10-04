import SwiftUI
import WindowKit

/// What a Windows settings page shows.
enum WindowsPageContent: Equatable {
    /// Only the "Windows is off" banner: Loop's page isn't built, so nothing in WindowKit is created.
    case offBanner
    case loopPage(WindowSettingsPage)
}

extension SettingsPage {
    /// The Loop page behind a Windows settings page; nil for Mooring's own pages.
    var windowSettingsPage: WindowSettingsPage? {
        switch self {
        case .windowsBehavior: .behavior
        case .windowsKeybinds: .keybinds
        case .windowsGestures: .gestures
        case .windowsRadialMenu: .radialMenu
        case .windowsPreview: .preview
        case .windowsExcludedApps: .excludedApps
        case .general, .shortcuts, .keepAwake, .lidAndBattery, .agents, .advanced: nil
        }
    }

    /// Behavior carries the Window Manager switch at the top, in every state.
    var hasWindowManagerToggle: Bool {
        self == .windowsBehavior
    }

    /// Loop's page once Windows is on; the off banner alone otherwise.
    func windowsContent(for state: WindowsController.State) -> WindowsPageContent? {
        guard let page = windowSettingsPage else { return nil }
        return state == .on ? .loopPage(page) : .offBanner
    }
}

/// One page of Settings → Windows (docs/superpowers/specs/2026-10-03-stage-3a-windowkit-design.md,
/// "Settings → Windows"). Loop's Luminare page is hosted directly in the detail area.
struct WindowsSettingsPage: View {
    let page: SettingsPage
    let windows: WindowsController
    /// Builds Loop's page; called only while Windows is on. Tests inject a counting builder.
    var loopPage: @MainActor (WindowSettingsPage) -> AnyView = WindowSettingsPage.view

    var body: some View {
        VStack(spacing: 0) {
            if page.hasWindowManagerToggle {
                WindowManagerToggle(windows: windows)
                Divider()
            }
            switch page.windowsContent(for: windows.state) {
            case .offBanner:
                WindowsPageBanner(turnOn: windows.turnOn)
            case .loopPage(let page):
                loopPage(page)
            case nil:
                EmptyView()
            }
        }
        .navigationTitle(page.title)
    }
}

/// "Window Manager": on turns Windows on (asking for Accessibility if needed), off turns it off.
/// It shows whether Windows is wanted, so it reads on (and can be turned off) while Windows waits for Accessibility.
struct WindowManagerToggle: View {
    static let title = "Window Manager"

    let windows: WindowsController

    static func isOn(_ windows: WindowsController) -> Binding<Bool> {
        Binding(get: { windows.state != .off }, set: { $0 ? windows.turnOn() : windows.turnOff() })
    }

    var body: some View {
        HStack {
            Text(Self.title)
            Spacer()
            Toggle(Self.title, isOn: Self.isOn(windows))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }
}

/// Shown in place of Loop's page while Windows isn't on.
struct WindowsPageBanner: View {
    static let title = "Windows is off"
    static let turnOnTitle = "Turn On…"

    let turnOn: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent(Self.title) {
                    Button(Self.turnOnTitle, action: turnOn)
                }
            }
        }
        .formStyle(.grouped)
    }
}

import SwiftUI
import WindowKit

/// What a Windows settings page shows.
enum WindowsPageContent: Equatable {
    /// Only the "Windows is off" banner: Loop's page isn't built, so nothing in WindowKit is created.
    case offBanner
    /// Windows is on but this Mac can't run the page's feature: a banner with this title, and no Loop page.
    case unavailableBanner(String)
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
        case .general, .shortcuts, .keepAwake, .lidAndBattery, .agents, .advanced,
             .clipboardHistory, .clipboardIgnoreRules, .clipboardAppearance: nil
        }
    }

    /// Behavior carries the Window Manager switch at the top, in every state.
    var hasWindowManagerToggle: Bool {
        self == .windowsBehavior
    }

    /// Loop's page once Windows is on; the off banner alone otherwise. Gestures needs MultitouchSupport,
    /// which is only asked about once Windows is on.
    func windowsContent(for state: WindowsController.State,
                        gesturesAvailable: @autoclosure () -> Bool = true) -> WindowsPageContent? {
        guard let page = windowSettingsPage else { return nil }
        guard state == .on else { return .offBanner }
        if page == .gestures && !gesturesAvailable() {
            return .unavailableBanner(WindowsPageBanner.gesturesUnavailableTitle)
        }
        return .loopPage(page)
    }
}

/// One page of Settings → Windows (docs/superpowers/specs/2026-10-03-stage-3a-windowkit-design.md,
/// "Settings → Windows"). Loop's Luminare page is hosted directly in the detail area.
struct WindowsSettingsPage: View {
    let page: SettingsPage
    let windows: WindowsController
    /// Builds Loop's page; called only while Windows is on. Tests inject a counting builder.
    var loopPage: @MainActor (WindowSettingsPage) -> AnyView = WindowSettingsPage.view
    /// Whether MultitouchSupport loaded; asked only while Windows is on. Tests inject an answer.
    var gesturesAvailable: @MainActor () -> Bool = { WindowKit.gesturesAvailable }

    var body: some View {
        VStack(spacing: 0) {
            if page.hasWindowManagerToggle {
                WindowManagerToggle(windows: windows)
                Divider()
            }
            switch page.windowsContent(for: windows.state, gesturesAvailable: gesturesAvailable()) {
            case .offBanner:
                WindowsPageBanner(turnOn: windows.turnOn)
            case .unavailableBanner(let title):
                WindowsPageBanner(title: title, turnOn: nil)
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

/// Shown in place of Loop's page while Windows isn't on, or when this Mac can't run the page's feature.
struct WindowsPageBanner: View {
    static let title = "Windows is off"
    static let turnOnTitle = "Turn On…"
    static let gesturesUnavailableTitle = "Gestures aren't available on this Mac"

    var title = Self.title
    /// Nil when there's nothing to turn on.
    let turnOn: (() -> Void)?

    var body: some View {
        Form {
            Section {
                LabeledContent(title) {
                    if let turnOn {
                        Button(Self.turnOnTitle, action: turnOn)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

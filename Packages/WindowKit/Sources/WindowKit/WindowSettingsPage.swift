import Luminare
import SwiftUI

/// Loop's Luminare settings pages, as Mooring's Settings → Windows group shows them.
public enum WindowSettingsPage: CaseIterable, Sendable {
    case behavior, keybinds, gestures, radialMenu, preview, excludedApps

    /// Behavior includes Loop's Advanced page, and Radial Menu includes its Accent Color page.
    @MainActor
    public static func view(_ page: WindowSettingsPage) -> AnyView {
        let content: AnyView = switch page {
        case .behavior:
            AnyView(LuminareForm {
                BehaviorConfigurationView().luminareFormLayout(.none)
                AdvancedConfigurationView().luminareFormLayout(.none)
            })
        case .keybinds:
            AnyView(KeybindsConfigurationView())
        case .gestures:
            AnyView(GesturesConfigurationView())
        case .radialMenu:
            AnyView(LuminareForm {
                RadialMenuConfigurationView().luminareFormLayout(.none)
                AccentColorConfigurationView().luminareFormLayout(.none)
            })
        case .preview:
            AnyView(PreviewConfigurationView())
        case .excludedApps:
            AnyView(ExcludedAppsConfigurationView())
        }

        return AnyView(content.environmentObject(SettingsWindowManager.shared))
    }
}

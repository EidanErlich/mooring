import AwakeKit
import SwiftUI

/// The Settings sidebar (docs/SPEC.md, "Settings window").
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, shortcuts, keepAwake, lidAndBattery, agents
    case windowsBehavior, windowsKeybinds, windowsGestures, windowsRadialMenu, windowsPreview, windowsExcludedApps
    case clipboardHistory, clipboardIgnoreRules, clipboardAppearance
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .keepAwake: "Keep Awake"
        case .lidAndBattery: "Lid & Battery"
        case .agents: "Agents"
        case .windowsBehavior: "Behavior"
        case .windowsKeybinds: "Keybinds"
        case .windowsGestures: "Gestures"
        case .windowsRadialMenu: "Radial Menu"
        case .windowsPreview: "Preview"
        case .windowsExcludedApps: "Excluded Apps"
        case .clipboardHistory: "History"
        case .clipboardIgnoreRules: "Ignore Rules"
        case .clipboardAppearance: "Appearance"
        case .advanced: "Advanced"
        }
    }

    var group: String {
        switch self {
        case .general, .shortcuts: "General"
        case .keepAwake, .lidAndBattery, .agents: "Awake"
        case .windowsBehavior, .windowsKeybinds, .windowsGestures, .windowsRadialMenu, .windowsPreview,
             .windowsExcludedApps: "Windows"
        case .clipboardHistory, .clipboardIgnoreRules, .clipboardAppearance: "Clipboard"
        case .advanced: "Mooring"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .keepAwake: "sun.max"
        case .lidAndBattery: "laptopcomputer"
        case .agents: "sparkles"
        case .windowsBehavior: "macwindow"
        case .windowsKeybinds: "keyboard"
        case .windowsGestures: "hand.draw"
        case .windowsRadialMenu: "circle.circle"
        case .windowsPreview: "inset.filled.center.rectangle"
        case .windowsExcludedApps: "xmark.octagon"
        case .clipboardHistory: "clock.arrow.circlepath"
        case .clipboardIgnoreRules: "eye.slash"
        case .clipboardAppearance: "paintbrush"
        case .advanced: "wrench.and.screwdriver"
        }
    }
}

/// What a left click turns On with.
enum ClickLevelOption: CaseIterable {
    case system, screenOn, lidClosed

    var level: AwakeLevel {
        switch self {
        case .system: .system
        case .screenOn: .screenOn
        case .lidClosed: AwakeLevel(display: false, lid: true)
        }
    }

    var title: String {
        switch self {
        case .system: "Keep the Mac awake"
        case .screenOn: "Keep the Mac and screen awake"
        case .lidClosed: "Keep the Mac awake with the lid closed"
        }
    }

    init(level: AwakeLevel) {
        self = level.lid ? .lidClosed : (level.display ? .screenOn : .system)
    }
}

/// The selected page, shared so the window can be opened on a given page.
@MainActor @Observable
final class SettingsNavigation {
    var selection: SettingsPage? = .general
}

struct SettingsView: View {
    let engine: AwakeEngine?
    let windows: WindowsController?
    let clipboard: ClipboardController?
    @Bindable var navigation: SettingsNavigation

    private var groups: [String] {
        SettingsPage.allCases.map(\.group).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(SettingsPage.allCases.filter { $0.group == group }) { page in
                            Label(page.title, systemImage: page.systemImage).tag(page)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            let page = navigation.selection ?? .general
            switch page {
            case .general: GeneralSettingsPage()
            case .shortcuts: ShortcutsSettingsPage(windows: windows, clipboard: clipboard)
            case .keepAwake: KeepAwakeSettingsPage()
            case .lidAndBattery: LidBatterySettingsPage()
            case .agents: AgentsSettingsPage()
            case .windowsBehavior, .windowsKeybinds, .windowsGestures, .windowsRadialMenu, .windowsPreview,
                 .windowsExcludedApps:
                if let windows {
                    WindowsSettingsPage(page: page, windows: windows)
                }
            case .clipboardHistory, .clipboardIgnoreRules, .clipboardAppearance:
                if let clipboard {
                    ClipboardSettingsPage(page: page, clipboard: clipboard)
                }
            case .advanced: AdvancedSettingsPage(engine: engine)
            }
        }
    }
}

import AwakeKit
import SwiftUI

/// The Settings sidebar (docs/SPEC.md, "Settings window"). Windows, Clipboard
/// and Shortcuts pages arrive with their stages.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, keepAwake, lidAndBattery, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .keepAwake: "Keep Awake"
        case .lidAndBattery: "Lid & Battery"
        case .advanced: "Advanced"
        }
    }

    var group: String {
        switch self {
        case .general: "General"
        case .keepAwake, .lidAndBattery: "Awake"
        case .advanced: "Mooring"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .keepAwake: "sun.max"
        case .lidAndBattery: "laptopcomputer"
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

struct SettingsView: View {
    let engine: AwakeEngine?
    @State private var selection: SettingsPage? = .general

    private var groups: [String] {
        SettingsPage.allCases.map(\.group).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
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
            switch selection ?? .general {
            case .general: GeneralSettingsPage()
            case .keepAwake: KeepAwakeSettingsPage()
            case .lidAndBattery: LidBatterySettingsPage()
            case .advanced: AdvancedSettingsPage(engine: engine)
            }
        }
    }
}

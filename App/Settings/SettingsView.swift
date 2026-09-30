import AwakeKit
import SwiftUI

/// The Settings sidebar (docs/SPEC.md, "Settings window"). Stage 1b ships
/// General › General and Awake › Keep Awake; the other pages arrive with their stages.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, keepAwake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .keepAwake: "Keep Awake"
        }
    }

    var group: String {
        switch self {
        case .general: "General"
        case .keepAwake: "Awake"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .keepAwake: "sun.max"
        }
    }
}

/// What a left click turns On with. The lid option joins in stage 1c.
enum ClickLevelOption: CaseIterable {
    case system, screenOn

    var level: AwakeLevel {
        switch self {
        case .system: .system
        case .screenOn: .screenOn
        }
    }

    var title: String {
        switch self {
        case .system: "Keep the Mac awake"
        case .screenOn: "Keep the Mac and screen awake"
        }
    }

    init(level: AwakeLevel) {
        self = level.display ? .screenOn : .system
    }
}

struct SettingsView: View {
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
            }
        }
    }
}

import AppKit
import AwakeKit
import SwiftUI

/// The dropdown's content (docs/SPEC.md, "The dropdown is a custom panel").
/// Windows and Clipboard rows join in stages 3 and 4.
struct DropdownView: View {
    let engine: AwakeEngine
    let model: DropdownModel
    let openSettings: () -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            page
                .padding(6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(width: PanelPlacement.width, height: min(max(contentHeight, 1), model.maxHeight))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var page: some View {
        switch model.page {
        case .root: root
        case .awake: AwakeSectionView(engine: engine, model: model)
        }
    }

    private var root: some View {
        VStack(alignment: .leading, spacing: 2) {
            StatusHeader(engine: engine, model: model)
            Divider()
            MenuRow(title: "Awake", trailing: "›") { model.page = .awake }
            Divider()
            MenuRow(title: "Settings…", trailing: "⌘,", action: openSettings)
                .keyboardShortcut(",", modifiers: .command)
            MenuRow(title: "Quit Mooring", trailing: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}

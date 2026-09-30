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
        TimelineView(.animation(minimumInterval: 1, paused: !model.isPresented)) { context in
            ScrollView {
                page(now: context.date)
                    .padding(6)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(width: PanelPlacement.width, height: min(max(contentHeight, 1), model.maxHeight))
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func page(now: Date) -> some View {
        switch model.page {
        case .root: root(now: now)
        case .awake: AwakeSectionView(engine: engine, model: model, now: now)
        }
    }

    private func root(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: engine.state.systemAssertion ? "circle.fill" : "circle")
                    .foregroundStyle(engine.state.systemAssertion ? .green : .secondary)
                    .imageScale(.small)
                Text(StatusLine.text(leases: engine.leases, state: engine.state, now: now))
                    .font(.headline)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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

import AwakeKit
import Observation
import SwiftUI

/// State the dropdown keeps between openings.
@MainActor
@Observable
final class DropdownModel {
    enum Page { case root, awake }

    var page = Page.root
    var maxHeight: CGFloat = 600
    /// The duration row picked last, for its checkmark.
    var lastDuration: AwakeDuration?
}

/// One clickable row in the dropdown, styled like a menu item.
struct MenuRow: View {
    let title: String
    var systemImage: String?
    var trailing: String?
    var checked = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .opacity(checked ? 1 : 0)
                    .frame(width: 12)
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                Spacer()
                if let trailing { Text(trailing).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(hovering ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

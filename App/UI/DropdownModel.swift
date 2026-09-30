import AppKit
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
    /// Drives the countdown timeline, which is paused while the panel is hidden.
    private(set) var isPresented = false
    /// The duration row picked last, for its checkmark.
    var lastPick = DurationPick.none

    func didOpen(maxHeight: CGFloat) {
        self.maxHeight = maxHeight
        page = .root
        isPresented = true
    }

    func didClose() {
        isPresented = false
        page = .root
    }
}

/// The duration row picked last and the expiry it produced. The checkmark follows
/// the pick only while the menu lease still has that expiry; any other change
/// (left click, restore, ✕, expiry) falls back to "Until turned off" when it applies.
struct DurationPick: Equatable {
    var duration: AwakeDuration?
    var expiresAt: Date?

    static let none = DurationPick(duration: nil, expiresAt: nil)

    func isChecked(_ row: AwakeDuration, menuLease: Lease?) -> Bool {
        guard let menuLease else { return false }
        if let duration, expiresAt == menuLease.expiresAt { return row == duration }
        return row == .untilTurnedOff && menuLease.expiresAt == nil
    }
}

/// One clickable row in the dropdown, styled like a menu item.
struct MenuRow: View {
    let title: String
    var systemImage: String?
    var icon: NSImage?
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
                if let icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
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

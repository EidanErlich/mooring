import AppKit
import AwakeKit
import SwiftUI

/// One clickable row in the dropdown menu. The menu's own highlight decides `highlighted`.
struct MenuRow: View {
    let title: String
    var systemImage: String?
    var icon: NSImage?
    var trailing: String?
    var checked = false
    var highlighted = false
    let action: () -> Void

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
                if let trailing { Text(trailing).foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary)) }
            }
            .foregroundStyle(highlighted ? .white : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 5)
        }
        .buttonStyle(.plain)
    }
}

/// A switch row. The whole row is the click target, since clicking a switch's label
/// does nothing on macOS. The switch only shows the state: it ignores clicks, so the
/// button gets every one and the value toggles exactly once.
struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack {
                Text(title)
                Spacer()
                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // VoiceOver sees one switch with the title and value, not a button around a switch.
        .accessibilityRepresentation { Toggle(title, isOn: $isOn) }
    }
}

/// The dot and status line at the top of the menu.
struct StatusHeader: View {
    let engine: AwakeEngine
    let model: DropdownModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !model.isOpen)) { context in
            HStack(spacing: 6) {
                Image(systemName: engine.state.systemAssertion ? "circle.fill" : "circle")
                    .foregroundStyle(engine.state.systemAssertion ? .green : .secondary)
                    .imageScale(.small)
                Text(StatusLine.text(leases: engine.leases, state: engine.state, now: context.date))
                    .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
}

/// One anchored lease: who holds it, why, how long is left, and a button to end it.
/// It reads the lease by id in its body, so a renewed lease updates the same row. The
/// row can outlive its lease for a moment, until the menu syncs.
struct LeaseRow: View {
    let engine: AwakeEngine
    let model: DropdownModel
    let id: String
    /// Whether a lid-mode approval is pending for a lease id; read in the body, so the row follows it.
    var pendingApproval: (String) -> Bool = { _ in false }

    /// The time text, or the approval wait that replaces it.
    static func trailingText(for lease: Lease, pending: Bool, now: Date) -> String {
        pending ? "waiting for your approval" : LeaseText.timeLeft(lease, now: now)
    }

    var body: some View {
        if let lease = engine.leases.first(where: { $0.id == id }) {
            TimelineView(.animation(minimumInterval: 1, paused: !model.isOpen)) { context in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LeaseText.owner(lease.owner)).font(.caption).foregroundStyle(.secondary)
                        Text(lease.reason).lineLimit(1)
                    }
                    Spacer()
                    Text(Self.trailingText(for: lease, pending: pendingApproval(id), now: context.date))
                        .foregroundStyle(.secondary).monospacedDigit()
                    Button { engine.release(id: id) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("End this")
                }
                .padding(.horizontal, 14)
            }
        } else {
            EmptyView()
        }
    }
}

/// The "While an app runs…" row title once apps are picked.
enum AppSessionText {
    static func rowTitle(appNames: [String]) -> String {
        switch appNames.count {
        case 0: "While an app runs…"
        case 1: "While \(appNames[0]) runs"
        case 2: "While \(appNames[0]) and \(appNames[1]) run"
        default: "While \(appNames.count) apps run"
        }
    }
}

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

/// A switch row. The switch is the control, so the row has no highlight.
struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
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
struct LeaseRow: View {
    let engine: AwakeEngine
    let model: DropdownModel
    let lease: Lease

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !model.isOpen)) { context in
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(LeaseText.owner(lease.owner)).font(.caption).foregroundStyle(.secondary)
                    Text(lease.reason).lineLimit(1)
                }
                Spacer()
                Text(LeaseText.timeLeft(lease, now: context.date)).foregroundStyle(.secondary).monospacedDigit()
                Button { engine.release(id: lease.id) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("End this")
            }
            .padding(.horizontal, 14)
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

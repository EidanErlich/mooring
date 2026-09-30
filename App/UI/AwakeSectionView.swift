import AppKit
import AwakeKit
import SwiftUI

/// The Awake section (docs/SPEC.md, UX table). Lid rows join in stage 1c.
struct AwakeSectionView: View {
    let engine: AwakeEngine
    let model: DropdownModel
    let now: Date

    @State private var showingApps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuRow(title: "Awake", systemImage: "chevron.left") { model.page = .root }
                .font(.headline)
            Divider()
            Toggle("On", isOn: Binding(get: { engine.menuLease != nil }, set: { _ in engine.toggleMenu() }))
                .toggleStyle(.switch)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            ForEach(AwakeDuration.allCases, id: \.self) { duration in
                MenuRow(title: duration.title, checked: isChecked(duration)) {
                    model.lastDuration = duration
                    engine.turnOnMenu(duration: duration.interval)
                }
            }
            Divider()
            MenuRow(title: "While an app runs…", trailing: showingApps ? "⌄" : "›") { showingApps.toggle() }
            if showingApps {
                ForEach(runningApps(), id: \.processIdentifier) { app in
                    AppRow(app: app) {
                        engine.anchor(whileAppRuns: app.processIdentifier, appName: app.localizedName ?? "App")
                        showingApps = false
                    }
                }
            }
            Toggle(
                "Keep screen on",
                isOn: Binding(get: { engine.menuLease?.level.display ?? false }, set: { engine.setKeepScreenOn($0) })
            )
            .toggleStyle(.switch)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            Divider()
            anchored
        }
    }

    private var anchored: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Anchored").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            if engine.leases.isEmpty {
                Text("Nothing anchored").foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            ForEach(engine.leases) { lease in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LeaseText.owner(lease.owner)).font(.caption).foregroundStyle(.secondary)
                        Text(lease.reason).lineLimit(1)
                    }
                    Spacer()
                    Text(LeaseText.timeLeft(lease, now: now)).foregroundStyle(.secondary).monospacedDigit()
                    Button { engine.release(id: lease.id) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("End this")
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 4)
    }

    private func isChecked(_ duration: AwakeDuration) -> Bool {
        guard let menu = engine.menuLease else { return false }
        if let last = model.lastDuration { return last == duration }
        return duration == .untilTurnedOff && menu.expiresAt == nil
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { ($0.localizedName ?? "") .localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }
}

private struct AppRow: View {
    let app: NSRunningApplication
    let action: () -> Void

    var body: some View {
        MenuRow(title: app.localizedName ?? "App", action: action)
            .overlay(alignment: .leading) {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16).padding(.leading, 26)
                }
            }
    }
}

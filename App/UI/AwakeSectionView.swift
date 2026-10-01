import AppKit
import AwakeKit
import SwiftUI

/// The Awake section (docs/SPEC.md, UX table). The menu session is either a duration
/// or the picked apps; the rows show which one is active.
struct AwakeSectionView: View {
    let engine: AwakeEngine
    let model: DropdownModel

    @State private var showingApps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuRow(title: "Awake", systemImage: "chevron.left") { model.page = .root }
                .font(.headline)
            Divider()
            SwitchRow(title: "On", isOn: Binding(get: { engine.hasMenuSession }, set: { _ in engine.toggleMenu() }))
            ForEach(AwakeDuration.allCases, id: \.self) { duration in
                MenuRow(title: duration.title, checked: model.lastPick.isChecked(duration, menuLease: engine.menuLease)) {
                    engine.turnOnMenu(duration: duration.interval)
                    model.lastPick = DurationPick(duration: duration, expiresAt: engine.menuLease?.expiresAt)
                }
            }
            Divider()
            MenuRow(title: AppSessionText.rowTitle(appNames: DropdownMenu.pickedAppNames(engine)), trailing: showingApps ? "⌄" : "›",
                    checked: !engine.sessionApps.isEmpty) { showingApps.toggle() }
            if showingApps {
                ForEach(DropdownMenu.regularApps(), id: \.processIdentifier) { app in
                    AppRow(app: app, picked: DropdownMenu.isPicked(engine, app)) { DropdownMenu.togglePick(engine, model, app) }
                }
            }
            SwitchRow(
                title: "Keep screen on",
                isOn: Binding(get: { engine.sessionLevel?.display ?? false }, set: { engine.setKeepScreenOn($0) })
            )
            lidRows
            Divider()
            anchored
        }
    }

    /// Lid mode needs the approved helper; until then one row walks through approval.
    @ViewBuilder
    private var lidRows: some View {
        if HelperClient.shared.status == .enabled {
            SwitchRow(
                title: "Allow lid close",
                isOn: Binding(get: { engine.sessionLevel?.lid ?? false }, set: { enabled in
                    guard !enabled || DropdownMenu.confirmLidOnBattery(engine) else { return }
                    engine.setAllowLidClose(enabled)
                })
            )
            MenuRow(title: "Until I open the lid") {
                guard DropdownMenu.confirmLidOnBattery(engine) else { return }
                engine.startLidSession()
            }
        } else {
            MenuRow(title: "Approve lid mode…") {
                try? HelperClient.shared.register()
                HelperClient.shared.openLoginItemsSettings()
            }
        }
    }

    private var anchored: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Anchored").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            if engine.leases.isEmpty {
                Text("Nothing anchored").foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            ForEach(engine.leases) { lease in
                LeaseRow(engine: engine, model: model, lease: lease)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AppRow: View {
    let app: NSRunningApplication
    let picked: Bool
    let action: () -> Void

    var body: some View {
        MenuRow(title: app.localizedName ?? "App", icon: app.icon, checked: picked, action: action)
    }
}

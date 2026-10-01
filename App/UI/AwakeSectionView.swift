import AppKit
import AwakeKit
import Defaults
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
            MenuRow(title: AppSessionText.rowTitle(appNames: pickedAppNames), trailing: showingApps ? "⌄" : "›",
                    checked: !engine.sessionApps.isEmpty) { showingApps.toggle() }
            if showingApps {
                ForEach(runningApps(), id: \.processIdentifier) { app in
                    AppRow(app: app, picked: isPicked(app)) { togglePick(app) }
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
                    guard !enabled || confirmLidOnBattery() else { return }
                    engine.setAllowLidClose(enabled)
                })
            )
            MenuRow(title: "Until I open the lid") {
                guard confirmLidOnBattery() else { return }
                engine.startLidSession()
            }
        } else {
            MenuRow(title: "Approve lid mode…") {
                try? HelperClient.shared.register()
                HelperClient.shared.openLoginItemsSettings()
            }
        }
    }

    /// On battery without the opt-in, asks once. "Only on AC" still turns lid mode on;
    /// the lidNeedsAC guardrail holds it until the Mac is plugged in.
    private func confirmLidOnBattery() -> Bool {
        if LidOptIn.needsConfirmation(power: engine.power, settings: Defaults[.awake]) {
            _ = LidOptIn.confirm()
        }
        return true
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

    /// Names of the picked apps, from the running app when possible.
    private var pickedAppNames: [String] {
        engine.sessionApps.map { lease in
            lease.watch.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName }
                ?? String(lease.reason.dropFirst("While ".count).dropLast(" runs".count))
        }
    }

    private func isPicked(_ app: NSRunningApplication) -> Bool {
        engine.sessionApps.contains { $0.watch?.pid == app.processIdentifier }
    }

    /// Picking adds the app to the session (replacing a duration); picking again removes it.
    private func togglePick(_ app: NSRunningApplication) {
        if isPicked(app) {
            engine.release(id: "app-\(app.processIdentifier)")
        } else {
            engine.anchor(whileAppRuns: app.processIdentifier, appName: app.localizedName ?? "App")
            model.lastPick = .none
        }
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { ($0.localizedName ?? "") .localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
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

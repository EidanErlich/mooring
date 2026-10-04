import AppKit
import AwakeKit
import SwiftUI

/// The parts of Mooring › Advanced, in order.
enum AdvancedSection: Hashable {
    case updates, logs, diagnostics
}

/// Mooring › Advanced: updates (only with a Sparkle key), logs and diagnostics. (The spec's "log level" is
/// left out: os.Logger levels are controlled by the system, not the app.)
struct AdvancedSettingsPage: View {
    static let updatesToggleTitle = "Check for updates automatically"
    static let checkNowTitle = "Check Now"

    let engine: AwakeEngine?
    let updates: UpdatesController?
    @State private var exportResult: String?

    /// Updates appears only when a public key makes the updater available.
    static func sections(updates: UpdatesController?) -> [AdvancedSection] {
        (updates?.isAvailable == true ? [.updates] : []) + [.logs, .diagnostics]
    }

    var body: some View {
        Form {
            ForEach(Self.sections(updates: updates), id: \.self) { section in
                switch section {
                case .updates: if let updates { updatesSection(updates) }
                case .logs: logsSection
                case .diagnostics: diagnosticsSection
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
    }

    private func updatesSection(_ updates: UpdatesController) -> some View {
        Section("Updates") {
            Toggle(Self.updatesToggleTitle, isOn: Binding(
                get: { updates.checksAutomatically }, set: { updates.setChecksAutomatically($0) }))
            Button(Self.checkNowTitle) { updates.checkNow() }
        }
    }

    private var logsSection: some View {
        Section("Logs") {
            Button("Open Console") {
                if let console = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") {
                    NSWorkspace.shared.openApplication(at: console, configuration: .init())
                }
            }
            Text("Filter by the subsystem dev.mooring.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            Button("Export diagnostics…") { export() }
                .disabled(engine == nil)
            if let exportResult {
                Text(exportResult).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func export() {
        guard let engine else { return }
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "Mooring-diagnostics-\(formatter.string(from: Date())).zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportResult = "Collecting…"
        Task {
            let sleepDisabled = try? await HelperClient.shared.lidSleepDisabled()
            let logs = await Task.detached { Diagnostics.recentLogs() }.value
            let files = Diagnostics.collect(engine: engine, helperStatus: HelperClient.shared.status,
                                            sleepDisabled: sleepDisabled, logs: { logs })
            do {
                try Diagnostics.write(files, zipTo: url)
                exportResult = "Saved \(url.lastPathComponent)"
            } catch {
                exportResult = error.localizedDescription
            }
        }
    }
}

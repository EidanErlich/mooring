import AppKit
import AwakeKit
import SwiftUI

/// Mooring › Advanced: logs and diagnostics. (The spec's "log level" is left out:
/// os.Logger levels are controlled by the system, not the app.)
struct AdvancedSettingsPage: View {
    let engine: AwakeEngine?
    @State private var exportResult: String?

    var body: some View {
        Form {
            Section("Logs") {
                Button("Open Console") {
                    if let console = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") {
                        NSWorkspace.shared.openApplication(at: console, configuration: .init())
                    }
                }
                Text("Filter by the subsystem dev.mooring.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                Button("Export diagnostics…") { export() }
                    .disabled(engine == nil)
                if let exportResult {
                    Text(exportResult).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
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

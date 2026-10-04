import AppKit
import AwakeKit
import SwiftUI

/// The parts of Mooring › Advanced, in order.
enum AdvancedSection: Hashable {
    case updates, logs, diagnostics, uninstall
}

/// Mooring › Advanced: updates (only with a Sparkle key), logs, diagnostics and uninstall. (The spec's "log level"
/// is left out: os.Logger levels are controlled by the system, not the app.)
struct AdvancedSettingsPage: View {
    static let updatesToggleTitle = "Check for updates automatically"
    static let checkNowTitle = "Check Now"
    static let uninstallTitle = "Uninstall Mooring…"

    let engine: AwakeEngine?
    let updates: UpdatesController?
    @State private var exportResult: String?
    @State private var uninstall: UninstallModel

    init(engine: AwakeEngine?, updates: UpdatesController?, uninstall: UninstallModel = .live()) {
        self.engine = engine
        self.updates = updates
        _uninstall = State(initialValue: uninstall)
    }

    /// Updates appears only when a public key makes the updater available.
    static func sections(updates: UpdatesController?) -> [AdvancedSection] {
        (updates?.isAvailable == true ? [.updates] : []) + [.logs, .diagnostics, .uninstall]
    }

    var body: some View {
        Form {
            ForEach(Self.sections(updates: updates), id: \.self) { section in
                switch section {
                case .updates: if let updates { updatesSection(updates) }
                case .logs: logsSection
                case .diagnostics: diagnosticsSection
                case .uninstall: uninstallSection
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
        .sheet(isPresented: $uninstall.isPresented) { UninstallSheet(model: uninstall) }
    }

    private var uninstallSection: some View {
        Section("Uninstall") {
            Button(Self.uninstallTitle, role: .destructive) { uninstall.present() }
            Text("Removes everything Mooring set up on this Mac, then moves the app to the Trash.")
                .font(.caption).foregroundStyle(.secondary)
        }
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

/// The confirmation for "Uninstall Mooring…": what will happen, the clipboard checkbox, Uninstall and Cancel.
struct UninstallSheet: View {
    @Bindable var model: UninstallModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Uninstall Mooring?").font(.headline)
            Text("Mooring will:")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(UninstallModel.plannedSteps, id: \.self) { step in
                    Text("• \(step)").fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Also delete clipboard history", isOn: $model.deleteClipboardHistory)
                .disabled(model.isRunning)
            HStack {
                if model.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Uninstalling…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Uninstall", role: .destructive) { Task { await model.uninstall() } }
            }
            .disabled(model.isRunning)
        }
        .padding(20)
        .frame(width: 440)
        .interactiveDismissDisabled(model.isRunning)
    }
}

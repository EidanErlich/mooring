import AwakeKit
import Defaults
import SwiftUI

/// Awake › Lid & Battery (docs/SPEC.md 1.7, 1.9): the helper, and the guardrails.
struct LidBatterySettingsPage: View {
    @Default(.awake) private var awake
    @State private var status = HelperClient.shared.status
    @State private var helperError: String?

    private static let lidThresholds: [Int?] = [nil, 10, 15, 20, 25, 30]
    private static let allThresholds: [Int?] = [nil, 5, 10, 15]

    var body: some View {
        Form {
            Section("Helper") {
                LabeledContent("Lid mode helper", value: statusText)
                if status == .enabled {
                    Button("Uninstall helper…", role: .destructive) { uninstall() }
                } else {
                    Button("Approve…") {
                        try? HelperClient.shared.register()
                        HelperClient.shared.openLoginItemsSettings()
                        status = HelperClient.shared.status
                    }
                }
                if let helperError {
                    Text(helperError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Battery") {
                Toggle("Allow lid mode on battery", isOn: $awake.allowLidOnBattery)
                Picker("Pause lid mode below", selection: $awake.lidBatteryThreshold) {
                    ForEach(Self.lidThresholds, id: \.self) { Text(Self.label($0)).tag($0) }
                }
                Picker("Pause Mooring below", selection: $awake.allBatteryThreshold) {
                    ForEach(Self.allThresholds, id: \.self) { Text(Self.label($0)).tag($0) }
                }
            }
            Section("Heat") {
                Toggle("Pause lid mode when the Mac runs hot", isOn: $awake.thermalCutoff)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Lid & Battery")
        .onAppear { status = HelperClient.shared.status }
    }

    private var statusText: String {
        switch status {
        case .enabled: "Enabled"
        case .requiresApproval: "Waiting for approval in Login Items & Extensions"
        case .notRegistered: "Not installed"
        case .notFound: "Not found"
        }
    }

    private static func label(_ threshold: Int?) -> String {
        threshold.map { "\($0)%" } ?? "Off"
    }

    private func uninstall() {
        Task {
            do {
                try await SettingsWindowController.shared.lid?.uninstall()
                helperError = nil
            } catch {
                helperError = error.localizedDescription
            }
            status = HelperClient.shared.status
        }
    }
}

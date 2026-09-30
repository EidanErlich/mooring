import Defaults
import ServiceManagement
import SwiftUI

struct GeneralSettingsPage: View {
    @Default(.swapClickActions) private var swapClickActions
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Swap left and right click", isOn: $swapClickActions)
                Text("Left click opens the menu; right click turns awake on or off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

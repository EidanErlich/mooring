import Defaults
import ServiceManagement
import SwiftUI

struct GeneralSettingsPage: View {
    @Default(.swapClickActions) private var swapClickActions
    @Default(.notifyGuardrails) private var notifyGuardrails
    @Default(.showTimeLeftInMenuBar) private var showTimeLeftInMenuBar
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var cliState = CLIInstaller.state(link: CLIInstaller.defaultLink, target: CLIInstaller.bundledBinary)
    @State private var cliError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Notify me when a guardrail pauses awake", isOn: $notifyGuardrails)
                Toggle("Show time left in the menu bar", isOn: $showTimeLeftInMenuBar)
            }
            Section {
                Toggle("Swap left and right click", isOn: $swapClickActions)
                Text("Left click opens the menu; right click turns awake on or off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            commandLineSection
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshCLIState)
        .navigationTitle("General")
    }

    private var commandLineSection: some View {
        Section("Command-line tool") {
            LabeledContent("Status") { Text(cliCaption).foregroundStyle(.secondary) }
            if cliState != .installed {
                Button(cliState == .missing ? "Install command-line tool" : "Reinstall", action: installCLI)
                    .disabled(cliState == .notALink || BundleLocation.isRunningTransient)
                if BundleLocation.isRunningTransient {
                    Text(BundleLocation.moveCaption).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let cliError {
                Text(cliError).font(.caption).foregroundStyle(.red)
            }
            Text("If your shell can't find `mooring`, add this line to ~/.zshrc:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(CLIInstaller.pathLine).font(.caption.monospaced()).textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CLIInstaller.pathLine, forType: .string)
                }
            }
        }
    }

    private var cliCaption: String {
        switch cliState {
        case .installed: "Installed at ~/.local/bin/mooring"
        case .missing: "Not installed"
        case .pointsElsewhere(let path): "Points to \(path)"
        case .notALink: "Not a link (Mooring won't replace it)"
        }
    }

    private func refreshCLIState() {
        cliState = CLIInstaller.state(link: CLIInstaller.defaultLink, target: CLIInstaller.bundledBinary)
    }

    private func installCLI() {
        do {
            try CLIInstaller.install(link: CLIInstaller.defaultLink, target: CLIInstaller.bundledBinary)
            cliError = nil
        } catch {
            cliError = error.localizedDescription
        }
        refreshCLIState()
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

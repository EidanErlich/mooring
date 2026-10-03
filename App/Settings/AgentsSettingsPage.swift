import AwakeKit
import Defaults
import SwiftUI

/// Awake › Agents: installs the Claude Code plugin and sets how agent sessions keep the Mac awake.
struct AgentsSettingsPage: View {
    @Default(.awake) private var awake
    @State private var status: ClaudePluginInstaller.Status?
    @State private var disabled = false
    @State private var installing = false
    @State private var error: String?
    @State private var updated = false

    let appVersion: String
    let bundlePlugin: String
    let runner: ToolRunning

    init(appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
         bundlePlugin: String = Bundle.main.resourceURL?.appendingPathComponent("ClaudePlugin").path ?? "",
         runner: ToolRunning = ProcessRunner()) {
        self.appVersion = appVersion
        self.bundlePlugin = bundlePlugin
        self.runner = runner
    }

    var body: some View {
        Form {
            Section("Claude Code") {
                LabeledContent("Plugin") {
                    HStack {
                        Text(statusText).foregroundStyle(.secondary)
                        if let title = status?.buttonTitle {
                            Button(title) { install() }.disabled(installing)
                        }
                        if installing { ProgressView().controlSize(.small) }
                    }
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                if updated {
                    Text("Restart Claude Code sessions to use the new version.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Keeps your Mac awake while Claude Code works. Installs Mooring's plugin into Claude Code.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Lid mode") {
                Toggle("Keep working with the lid closed", isOn: $awake.agentSessionLid)
                Text("Claude Code sessions keep the Mac awake with the lid closed while they work.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Lid mode for agents", selection: $awake.agentLidApproval) {
                    ForEach(AgentLidApproval.allCases, id: \.self) { Text(Self.label(for: $0)).tag($0) }
                }
                if !awake.agentLidAlwaysAllowed.isEmpty {
                    LabeledContent("Always allowed") {
                        VStack(alignment: .trailing) {
                            ForEach(awake.agentLidAlwaysAllowed, id: \.self) { agent in
                                HStack {
                                    Text(agent)
                                    Button("Remove") { awake.agentLidAlwaysAllowed.removeAll { $0 == agent } }
                                }
                            }
                        }
                    }
                }
                Text("Battery guardrails always apply: lid mode needs power until you allow it on battery, "
                    + "and pauses when the battery is low.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            MCPClientsSection(notificationsAllowed: $awake.agentNotifications)
            Section("Agents") {
                Picker("Keep awake while agents work", selection: $awake.agentKeepAwake) {
                    Text("Automatic").tag(AgentMode.automatic)
                    Text("Only when asked").tag(AgentMode.explicit)
                }
                Picker("When Claude is waiting for you, stay awake for", selection: $awake.agentWaitingTimeout) {
                    Text("10 min").tag(TimeInterval(600))
                    Text("30 min").tag(TimeInterval(1800))
                    Text("60 min").tag(TimeInterval(3600))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Agents")
        .task { await refresh() }
    }

    nonisolated static func label(for approval: AgentLidApproval) -> String {
        switch approval {
        case .askWhenOpenEnded: "Ask only when it has no end"
        case .alwaysAsk: "Always ask"
        case .alwaysAllow: "Always allow"
        case .never: "Never"
        }
    }

    private var statusText: String {
        guard let status else { return "Checking…" }
        return disabled ? "\(status.text) (disabled)" : status.text
    }

    /// Re-reads what Claude Code has installed, off the main thread.
    private func refresh() async {
        let (appVersion, runner) = (appVersion, runner)
        let (newStatus, newDisabled) = await Task.detached {
            let claude = ClaudePluginInstaller.findClaude()
            let list = claude.flatMap { ClaudePluginInstaller.readList(claude: $0, runner: runner) }
            return (ClaudePluginInstaller.status(listJSON: list, claudeFound: claude != nil, appVersion: appVersion),
                    ClaudePluginInstaller.isDisabled(listJSON: list))
        }.value
        status = newStatus
        disabled = newDisabled
    }

    private func install() {
        installing = true
        error = nil
        updated = false
        let wasUpdate = { if case .needsUpdate = status { return true } else { return false } }()
        let (bundlePlugin, runner) = (bundlePlugin, runner)
        Task {
            let result = await Task.detached { () -> Result<Void, ClaudePluginInstaller.InstallError> in
                guard let claude = ClaudePluginInstaller.findClaude() else { return .failure(.command("Claude Code not found")) }
                return ClaudePluginInstaller.install(claude: claude, bundlePlugin: bundlePlugin, runner: runner,
                                                     ensureCLI: ClaudePluginInstaller.ensureCLILinked)
            }.value
            switch result {
            case .failure(let failure): error = failure.message
            case .success: updated = wasUpdate
            }
            await refresh()
            installing = false
        }
    }
}

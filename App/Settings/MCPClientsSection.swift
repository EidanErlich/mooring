import AppKit
import Foundation
import MooringIPC
import Observation
import SwiftUI

/// What the "Other agents (MCP)" section shows: one row per MCP client Mooring can edit, and the actions on them.
@MainActor
@Observable
final class MCPClientsModel {
    struct Row: Equatable, Identifiable {
        let client: MCPClientConfig.Client
        var state: MCPClientConfig.State
        /// What the last action left to say: a restart hint or why it was refused.
        var message: String?

        var id: MCPClientConfig.Client { client }

        var name: String { MCPClientConfig(client: client, home: URL(fileURLWithPath: "/")).name }

        /// Nil when there is nothing to do, which is when the client isn't installed.
        var buttonTitle: String? {
            switch state {
            case .notInstalled: nil
            case .notAdded: "Add"
            case .added: "Remove"
            case .needsUpdate: "Update"
            }
        }
    }

    private(set) var rows: [Row] = []

    private let home: URL
    private let helperPath: String
    private let copy: (String) -> Void

    /// `helperPath` is the `mooring` that the config entries should run; `copy` puts text on the clipboard.
    init(home: URL, helperPath: String, copy: @escaping (String) -> Void) {
        self.home = home
        self.helperPath = helperPath
        self.copy = copy
        refresh()
    }

    /// The model for the running app: this app's helper, the user's home folder and the general pasteboard.
    static func live() -> MCPClientsModel {
        MCPClientsModel(
            home: FileManager.default.homeDirectoryForCurrentUser, helperPath: bundledHelperPath(in: Bundle.main.bundleURL)
        ) { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    nonisolated static func bundledHelperPath(in bundle: URL) -> String {
        bundle.appendingPathComponent("Contents/Helpers/mooring").path
    }

    /// Reads every client's state again, keeping the messages of rows whose state has not changed.
    func refresh() {
        rows = MCPClientConfig.Client.allCases.map { client in
            let state = config(client).state(helperPath: helperPath)
            let kept = rows.first { $0.client == client && $0.state == state }?.message
            return Row(client: client, state: state, message: kept)
        }
    }

    /// Adds, updates or removes `client`'s entry, depending on its row's state.
    func perform(_ client: MCPClientConfig.Client) {
        let config = config(client)
        let message: String?
        do {
            switch config.state(helperPath: helperPath) {
            case .notInstalled:
                message = nil
            case .notAdded, .needsUpdate:
                try config.add(helperPath: helperPath)
                message = "Restart \(config.name) to load it."
            case .added:
                try config.remove()
                message = nil
            }
        } catch MCPClientConfig.ConfigError.invalidJSON(let path) {
            message = "\(path) isn't valid JSON, so Mooring left it alone. Use Copy config instead."
        } catch {
            message = error.localizedDescription
        }
        refresh()
        if let index = rows.firstIndex(where: { $0.client == client }) { rows[index].message = message }
    }

    /// Copies the config snippet for clients that Mooring doesn't edit.
    func copyConfig() {
        copy(MCPClientConfig.snippet(helperPath: helperPath))
    }

    private func config(_ client: MCPClientConfig.Client) -> MCPClientConfig {
        MCPClientConfig(client: client, home: home)
    }
}

/// Settings › Agents › Other agents (MCP): one-click setup for Claude Desktop and Cursor, a snippet for the rest, and
/// whether agents may post notifications.
struct MCPClientsSection: View {
    @Binding var notificationsAllowed: Bool
    @State private var model: MCPClientsModel

    init(notificationsAllowed: Binding<Bool>, model: MCPClientsModel = .live()) {
        _notificationsAllowed = notificationsAllowed
        _model = State(initialValue: model)
    }

    var body: some View {
        Section("Other agents (MCP)") {
            ForEach(model.rows) { row in
                LabeledContent(row.name) {
                    HStack {
                        Text(Self.stateText(row.state)).foregroundStyle(.secondary)
                        if let title = row.buttonTitle { Button(title) { model.perform(row.client) } }
                    }
                }
                if let message = row.message {
                    Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Text("Mooring rewrites the file with sorted keys and keeps a .mooring-backup next to it.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Any other client") { Button("Copy config") { model.copyConfig() } }
            Text("Paste into your MCP client's config. Most clients call this file mcp.json.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Let agents post notifications", isOn: $notificationsAllowed)
        }
        .onAppear { model.refresh() }
    }

    static func stateText(_ state: MCPClientConfig.State) -> String {
        switch state {
        case .notInstalled: "Not installed"
        case .notAdded: "Not added"
        case .added: "Added"
        case .needsUpdate: "Needs update"
        }
    }
}

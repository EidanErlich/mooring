import Foundation

/// Pure parsing of the `claude` CLI's output, shared by the app's installer and `mooring doctor`.
public enum ClaudeCode {
    /// Where `claude` lives when the login shell can't find it. Callers expand the tilde.
    public static let candidatePaths = ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]

    /// The plugin installed from the app's bundled marketplace.
    public static let appPluginID = "mooring@mooring-app"
    /// The plugin installed from the GitHub marketplace.
    public static let repoPluginID = "mooring@mooring"
    /// The marketplace the app registers for its bundled copy of the plugin.
    public static let appMarketplaceName = "mooring-app"

    public struct InstalledPlugin: Equatable, Sendable {
        public var id: String
        public var version: String?
        public var enabled: Bool
        /// Where Claude Code keeps the plugin, e.g. `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>`.
        public var installPath: String?

        public init(id: String, version: String?, enabled: Bool, installPath: String?) {
            self.id = id
            self.version = version
            self.enabled = enabled
            self.installPath = installPath
        }
    }

    /// "2.1.284 (Claude Code)" → "2.1.284"; nil when the output doesn't start with a version.
    public static func parseVersion(_ output: String) -> String? {
        let firstLine = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let token = firstLine.split(separator: " ").first.map(String.init) ?? ""
        return token.range(of: #"^\d+(\.\d+)+$"#, options: .regularExpression) == nil ? nil : token
    }

    /// "2.1.284" → "2.1".
    public static func majorMinor(_ version: String) -> String? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0].allSatisfy(\.isNumber), parts[1].allSatisfy(\.isNumber),
              !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return "\(parts[0]).\(parts[1])"
    }

    /// Parses `claude plugin list --json`, ignoring fields it doesn't know. nil when it isn't a JSON array.
    public static func parsePluginList(_ json: Data) -> [InstalledPlugin]? {
        guard let items = (try? JSONSerialization.jsonObject(with: json)) as? [Any] else { return nil }
        return items.compactMap { item in
            guard let object = item as? [String: Any], let id = object["id"] as? String else { return nil }
            return InstalledPlugin(id: id, version: object["version"] as? String, enabled: object["enabled"] as? Bool ?? true,
                                   installPath: object["installPath"] as? String)
        }
    }

    /// The names in `claude plugin marketplace list --json`, ignoring fields it doesn't know. nil when it isn't a JSON array.
    public static func parseMarketplaceNames(_ json: Data) -> [String]? {
        guard let items = (try? JSONSerialization.jsonObject(with: json)) as? [Any] else { return nil }
        return items.compactMap { ($0 as? [String: Any])?["name"] as? String }
    }

    /// Mooring's plugin among the installed ones, preferring the copy installed from the app.
    public static func mooringPlugin(in plugins: [InstalledPlugin]) -> InstalledPlugin? {
        plugins.first { $0.id == appPluginID } ?? plugins.first { $0.id == repoPluginID }
    }
}

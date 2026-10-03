import Foundation

/// Reads and edits one MCP client's config file so that its `mcpServers` has a `mooring` entry.
/// Other keys and servers are left as they are; the first edit keeps a `.mooring-backup` copy.
public struct MCPClientConfig {
    public enum Client: CaseIterable, Sendable {
        case claudeDesktop, cursor
    }

    public enum State: Equatable, Sendable {
        case notInstalled, notAdded, added
        /// The entry exists with a different command (the associated value, when there is one).
        case needsUpdate(String?)
    }

    public enum ConfigError: Error, Equatable {
        /// The file isn't a JSON object; the payload is its display path.
        case invalidJSON(String)
    }

    public let client: Client
    private let home: URL
    private let fileManager: FileManager

    public init(client: Client, home: URL, fileManager: FileManager = .default) {
        self.client = client
        self.home = home
        self.fileManager = fileManager
    }

    public var name: String {
        switch client {
        case .claudeDesktop: "Claude Desktop"
        case .cursor: "Cursor"
        }
    }

    public var folderURL: URL {
        switch client {
        case .claudeDesktop: home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
        case .cursor: home.appendingPathComponent(".cursor", isDirectory: true)
        }
    }

    public var fileURL: URL {
        switch client {
        case .claudeDesktop: folderURL.appendingPathComponent("claude_desktop_config.json")
        case .cursor: folderURL.appendingPathComponent("mcp.json")
        }
    }

    /// Where the entry stands. A file that can't be read as a JSON object counts as not added.
    public func state(helperPath: String) -> State {
        var isFolder: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isFolder), isFolder.boolValue else { return .notInstalled }
        guard let root = try? readRoot(),
              let entry = (root["mcpServers"] as? [String: Any])?[Self.serverName] as? [String: Any] else { return .notAdded }
        let command = entry["command"] as? String
        return command == helperPath && entry["args"] as? [String] == Self.arguments ? .added : .needsUpdate(command)
    }

    /// Adds the entry, or points an existing one at `helperPath`. Throws when the client's folder is missing.
    public func add(helperPath: String) throws {
        guard fileManager.fileExists(atPath: folderURL.path) else { throw CocoaError(.fileNoSuchFile) }
        var root = try readRoot() ?? [:]
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[Self.serverName] = ["command": helperPath, "args": Self.arguments] as [String: Any]
        root["mcpServers"] = servers
        try write(root)
    }

    /// Removes the entry, and `mcpServers` too when that leaves it empty. Does nothing when there is no file.
    public func remove() throws {
        guard var root = try readRoot() else { return }
        guard var servers = root["mcpServers"] as? [String: Any], servers[Self.serverName] != nil else { return }
        servers[Self.serverName] = nil
        root["mcpServers"] = servers.isEmpty ? nil : servers
        try write(root)
    }

    /// The JSON to paste into a client this app doesn't edit.
    public static func snippet(helperPath: String) -> String {
        let root: [String: Any] = ["mcpServers": [serverName: ["command": helperPath, "args": arguments] as [String: Any]]]
        return (try? serialize(root)).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
    }

    private static let serverName = "mooring"
    private static let arguments = ["mcp"]
    private static let writeOptions: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    private static func serialize(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: writeOptions)
    }

    /// The file's top-level object, nil when the file doesn't exist (or is empty), or `invalidJSON` when it isn't an object.
    private func readRoot() throws -> [String: Any]? {
        guard let data = fileManager.contents(atPath: fileURL.path) else { return nil }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.invalidJSON(fileURL.path)
        }
        return root
    }

    /// Writes through a symlink to its target, keeps a backup of the first original and replaces the file atomically.
    private func write(_ root: [String: Any]) throws {
        let target = fileURL.resolvingSymlinksInPath()
        let backup = URL(fileURLWithPath: target.path + ".mooring-backup")
        if let original = fileManager.contents(atPath: target.path), !fileManager.fileExists(atPath: backup.path) {
            try original.write(to: backup, options: .atomic)
        }
        try Self.serialize(root).write(to: target, options: .atomic)
    }
}

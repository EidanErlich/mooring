import Foundation
import MooringIPC
import Testing

private let helper = "/Applications/Mooring.app/Contents/MacOS/mooring"

private func makeHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("mooring-mcp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

private func config(_ home: URL, _ client: MCPClientConfig.Client = .cursor, folder: Bool = true) throws -> MCPClientConfig {
    let value = MCPClientConfig(client: client, home: home)
    if folder { try FileManager.default.createDirectory(at: value.folderURL, withIntermediateDirectories: true) }
    return value
}

private func json(_ url: URL) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

@Test func pathsAndNames() throws {
    let home = URL(fileURLWithPath: "/h")
    let desktop = MCPClientConfig(client: .claudeDesktop, home: home)
    #expect(desktop.fileURL.path == "/h/Library/Application Support/Claude/claude_desktop_config.json")
    #expect(desktop.folderURL.path == "/h/Library/Application Support/Claude")
    #expect(desktop.name == "Claude Desktop")
    let cursor = MCPClientConfig(client: .cursor, home: home)
    #expect(cursor.fileURL.path == "/h/.cursor/mcp.json")
    #expect(cursor.name == "Cursor")
}

@Test func missingFolderIsNotInstalled() throws {
    let value = try config(makeHome(), folder: false)
    #expect(value.state(helperPath: helper) == .notInstalled)
    #expect(throws: (any Error).self) { try value.add(helperPath: helper) }
    #expect(!FileManager.default.fileExists(atPath: value.folderURL.path))
}

@Test func missingFileIsNotAdded() throws {
    let value = try config(makeHome())
    #expect(value.state(helperPath: helper) == .notAdded)
    try value.add(helperPath: helper)
    #expect(value.state(helperPath: helper) == .added)
    #expect(!FileManager.default.fileExists(atPath: value.fileURL.path + ".mooring-backup"))
}

@Test func addKeepsOtherServersAndBacksUp() throws {
    let value = try config(makeHome())
    let original = Data(#"{"mcpServers":{"other":{"command":"x"}},"theme":"dark"}"#.utf8)
    try original.write(to: value.fileURL)
    try value.add(helperPath: helper)

    let root = try json(value.fileURL)
    let servers = try #require(root["mcpServers"] as? [String: Any])
    #expect((servers["other"] as? [String: String]) == ["command": "x"])
    #expect(root["theme"] as? String == "dark")
    let mooring = try #require(servers["mooring"] as? [String: Any])
    #expect(mooring["command"] as? String == helper)
    #expect(mooring["args"] as? [String] == ["mcp"])
    #expect(try Data(contentsOf: URL(fileURLWithPath: value.fileURL.path + ".mooring-backup")) == original)
}

@Test func addedWithThisHelperIsAdded() throws {
    let value = try config(makeHome())
    try value.add(helperPath: helper)
    #expect(value.state(helperPath: helper) == .added)
}

@Test func otherCommandNeedsUpdate() throws {
    let value = try config(makeHome())
    try value.add(helperPath: "/old/mooring")
    #expect(value.state(helperPath: helper) == .needsUpdate("/old/mooring"))
    try value.add(helperPath: helper)
    #expect(value.state(helperPath: helper) == .added)
}

@Test func invalidJSONIsLeftAlone() throws {
    let value = try config(makeHome())
    let bad = Data("{ not json".utf8)
    try bad.write(to: value.fileURL)
    #expect(throws: MCPClientConfig.ConfigError.invalidJSON(value.fileURL.path)) { try value.add(helperPath: helper) }
    #expect(throws: MCPClientConfig.ConfigError.invalidJSON(value.fileURL.path)) { try value.remove() }
    #expect(try Data(contentsOf: value.fileURL) == bad)
}

@Test func removeDropsOnlyMooring() throws {
    let value = try config(makeHome())
    try Data(#"{"mcpServers":{"other":{"command":"x"}},"theme":"dark"}"#.utf8).write(to: value.fileURL)
    try value.add(helperPath: helper)
    try value.remove()
    var root = try json(value.fileURL)
    #expect((root["mcpServers"] as? [String: Any])?.keys.sorted() == ["other"])

    try value.add(helperPath: helper)
    try Data(#"{"mcpServers":{"mooring":{"command":"y"}},"theme":"dark"}"#.utf8).write(to: value.fileURL)
    try value.remove()
    root = try json(value.fileURL)
    #expect(root["mcpServers"] == nil)
    #expect(root["theme"] as? String == "dark")
    #expect(value.state(helperPath: helper) == .notAdded)
}

@Test func removeWithoutFileDoesNothing() throws {
    let value = try config(makeHome())
    try value.remove()
    #expect(!FileManager.default.fileExists(atPath: value.fileURL.path))
}

@Test func addWritesThroughSymlink() throws {
    let home = try makeHome()
    let value = try config(home)
    let dotfiles = home.appendingPathComponent("dotfiles")
    try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
    let target = dotfiles.appendingPathComponent("mcp.json")
    try Data(#"{"mcpServers":{}}"#.utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: value.fileURL, withDestinationURL: target)

    try value.add(helperPath: helper)
    _ = try FileManager.default.destinationOfSymbolicLink(atPath: value.fileURL.path)
    let servers = try #require(try json(target)["mcpServers"] as? [String: Any])
    #expect(servers["mooring"] != nil)
    try value.remove()
    _ = try FileManager.default.destinationOfSymbolicLink(atPath: value.fileURL.path)
}

@Test func addWritesThroughDanglingSymlink() throws {
    // A dotfiles repo that isn't checked out yet: the link points at a file, and a folder, that don't exist.
    let home = try makeHome()
    let value = try config(home)
    try FileManager.default.createSymbolicLink(atPath: value.fileURL.path, withDestinationPath: "../dotfiles/cursor/mcp.json")

    try value.add(helperPath: helper)

    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: value.fileURL.path) == "../dotfiles/cursor/mcp.json")
    let target = home.appendingPathComponent("dotfiles/cursor/mcp.json")
    let servers = try #require(try json(target)["mcpServers"] as? [String: Any])
    #expect(servers["mooring"] != nil)
    #expect(value.state(helperPath: helper) == .added)
}

@Test func snippetIsValidJSON() throws {
    let text = MCPClientConfig.snippet(helperPath: helper)
    let root = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    let mooring = try #require((root["mcpServers"] as? [String: Any])?["mooring"] as? [String: Any])
    #expect(mooring["args"] as? [String] == ["mcp"])
    #expect(mooring["command"] as? String == helper)
}

@Test func backupIsRefreshedOnEveryEdit() throws {
    let value = try config(makeHome())
    try Data(#"{"theme":"dark"}"#.utf8).write(to: value.fileURL)
    try value.add(helperPath: "/old/mooring")
    let beforeSecondEdit = try Data(contentsOf: value.fileURL)
    try value.add(helperPath: helper)
    #expect(try Data(contentsOf: URL(fileURLWithPath: value.fileURL.path + ".mooring-backup")) == beforeSecondEdit)
    let beforeRemove = try Data(contentsOf: value.fileURL)
    try value.remove()
    #expect(try Data(contentsOf: URL(fileURLWithPath: value.fileURL.path + ".mooring-backup")) == beforeRemove)
}

@Test func backupKeepsTheOriginalsPermissions() throws {
    let value = try config(makeHome())
    try Data(#"{"env":{"KEY":"secret"}}"#.utf8).write(to: value.fileURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: value.fileURL.path)
    try value.add(helperPath: helper)
    let backup = value.fileURL.path + ".mooring-backup"
    let attributes = try FileManager.default.attributesOfItem(atPath: backup)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func nonObjectServersAreNotReplaced() throws {
    let value = try config(makeHome())
    let original = Data(#"{"mcpServers": []}"#.utf8)
    try original.write(to: value.fileURL)
    #expect(throws: MCPClientConfig.ConfigError.invalidJSON(value.fileURL.path)) { try value.add(helperPath: helper) }
    #expect(try Data(contentsOf: value.fileURL) == original)
    #expect(!FileManager.default.fileExists(atPath: value.fileURL.path + ".mooring-backup"))
}

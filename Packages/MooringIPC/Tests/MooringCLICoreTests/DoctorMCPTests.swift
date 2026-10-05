import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

// Check 8: MCP clients

/// A temp home whose client folders exist, each holding a config that names `command` as the mooring server.
private final class MCPHome {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: try makeTempFolder())
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Creates the client's folder and, when `command` is given, a config file whose mooring entry runs it.
    func install(_ client: MCPClientConfig.Client, command: String? = nil) throws {
        let config = MCPClientConfig(client: client, home: url)
        try FileManager.default.createDirectory(at: config.folderURL, withIntermediateDirectories: true)
        guard let command else { return }
        let root = ["mcpServers": ["mooring": ["command": command, "args": ["mcp"]]]]
        try JSONSerialization.data(withJSONObject: root).write(to: config.fileURL)
    }
}

private func mcpCheck(home: MCPHome, helperPath: String = "/Apps/mooring") -> Doctor.Check {
    Doctor.checks(
        status: nil, pathEnv: nil, ownBinary: "/nowhere/mooring", resolve: { $0 }, claude: nil,
        home: home.url, helperPath: helperPath
    )[7]
}

@Test func mcpCheckPassesWithAddedClients() throws {
    let home = try MCPHome()
    try home.install(.claudeDesktop, command: "/Apps/mooring")
    try home.install(.cursor, command: "/Apps/mooring")
    #expect(mcpCheck(home: home) == Doctor.Check(name: "MCP clients", state: "pass", detail: "Claude Desktop, Cursor", fix: nil))
    try FileManager.default.removeItem(at: MCPClientConfig(client: .claudeDesktop, home: home.url).folderURL)
    #expect(mcpCheck(home: home).detail == "Cursor")
}

@Test func mcpCheckSkipsWhenNoneAdded() throws {
    let home = try MCPHome()
    #expect(mcpCheck(home: home) == Doctor.Check(name: "MCP clients", state: "skip", detail: "none added", fix: nil))
    try home.install(.cursor)
    #expect(mcpCheck(home: home).state == "skip")
}

@Test func mcpCheckFailsWhenNeedsUpdate() throws {
    let home = try MCPHome()
    try home.install(.claudeDesktop, command: "/Old/mooring")
    try home.install(.cursor, command: "/Old/mooring")
    #expect(mcpCheck(home: home) == Doctor.Check(
        name: "MCP clients", state: "fail", detail: "Claude Desktop needs update, Cursor needs update",
        fix: "Settings → Awake → Agents → Update"
    ))
    try home.install(.claudeDesktop, command: "/Apps/mooring")
    #expect(mcpCheck(home: home).detail == "Cursor needs update")
}

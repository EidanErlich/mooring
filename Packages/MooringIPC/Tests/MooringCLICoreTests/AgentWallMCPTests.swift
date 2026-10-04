import Foundation
import Testing

/// Part of the agent wall (App/Tests/AgentWallTests.swift): no MCP tool reaches clipboard history.
@Test func noClipboardMCPTools() async throws {
    let harness = MCPHarness()
    _ = await harness.run([initialize(), rpc(2, "tools/list")])
    let tools = try #require((harness.reply(2)?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
    let names = tools.compactMap { $0["name"] as? String }
    #expect(!names.isEmpty)
    let pattern = try Regex("clip|paste|history").ignoresCase()
    for name in names {
        #expect(name.firstMatch(of: pattern) == nil, "\(name) names the clipboard")
    }
}

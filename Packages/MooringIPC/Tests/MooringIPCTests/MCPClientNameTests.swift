import MooringIPC
import Testing

@Test func displayMapsKnownClients() {
    #expect(MCPClientName.display("claude-ai") == "Claude Desktop")
    #expect(MCPClientName.display("cursor-vscode") == "Cursor")
    #expect(MCPClientName.display("Zed") == "Zed")
}

@Test func displayFallsBackAndTruncates() {
    #expect(MCPClientName.display("") == "MCP client")
    #expect(MCPClientName.display(nil) == "MCP client")
    #expect(MCPClientName.display(String(repeating: "a", count: 60)).count == 40)
    #expect(MCPClientName.display("  Zed\u{7}\n ") == "Zed")
}

@Test func slugCollapsesAndTruncates() {
    #expect(MCPClientName.slug("Claude Desktop") == "claude-desktop")
    #expect(MCPClientName.slug("My Tool!!") == "my-tool")
    #expect(MCPClientName.slug(String(repeating: "b", count: 40)).count == 24)
    #expect(MCPClientName.slug("!!!") == "client")
}

@Test func slugNeverEndsWithADashAfterTruncation() {
    let slug = MCPClientName.slug("aaaaaaaaaaaaaaaaaaaaaaa b")
    #expect(slug == "aaaaaaaaaaaaaaaaaaaaaaa")
    #expect(!slug.hasSuffix("-"))
}

import Foundation
import MooringIPC
import Testing

private let listJSON = Data("""
[
  {"id":"context7@claude-plugins-official","version":"aa5654b7acb7","scope":"user","enabled":true,
   "installPath":"/Users/test/.claude/plugins/cache/claude-plugins-official/context7/aa5654b7acb7",
   "installedAt":"2026-09-30T17:15:16.780Z","mcpServers":{"context7":{"command":"npx"}},"projectEnabled":false},
  {"id":"mooring@mooring-app","version":"1.2.0","scope":"user","enabled":false,
   "installPath":"/Users/test/.claude/plugins/cache/mooring-app/mooring/1.2.0","lastUpdated":"2026-10-01T00:00:00Z"}
]
""".utf8)

@Test func parsesVersion() {
    #expect(ClaudeCode.parseVersion("2.1.284 (Claude Code)") == "2.1.284")
    #expect(ClaudeCode.parseVersion("2.1.285 (Claude Code)\n") == "2.1.285")
    #expect(ClaudeCode.parseVersion("") == nil)
    #expect(ClaudeCode.parseVersion("command not found") == nil)
}

@Test func majorMinor() {
    #expect(ClaudeCode.majorMinor("2.1.284") == "2.1")
    #expect(ClaudeCode.majorMinor("3.0") == "3.0")
    #expect(ClaudeCode.majorMinor("2") == nil)
    #expect(ClaudeCode.majorMinor("") == nil)
}

@Test func parsesPluginList() throws {
    let plugins = try #require(ClaudeCode.parsePluginList(listJSON))
    #expect(plugins.count == 2)
    #expect(plugins[0] == ClaudeCode.InstalledPlugin(
        id: "context7@claude-plugins-official", version: "aa5654b7acb7", enabled: true,
        installPath: "/Users/test/.claude/plugins/cache/claude-plugins-official/context7/aa5654b7acb7"))
    #expect(plugins[1].enabled == false)
    #expect(plugins[1].version == "1.2.0")
    let sparse = try #require(ClaudeCode.parsePluginList(Data(#"[{"id":"a@b"}]"#.utf8)))
    #expect(sparse == [ClaudeCode.InstalledPlugin(id: "a@b", version: nil, enabled: true, installPath: nil)])
    #expect(ClaudeCode.parsePluginList(Data("[]".utf8)) == [])
}

@Test func badListIsNil() {
    #expect(ClaudeCode.parsePluginList(Data("not json".utf8)) == nil)
    #expect(ClaudeCode.parsePluginList(Data(#"{"id":"mooring@mooring"}"#.utf8)) == nil)
    #expect(ClaudeCode.parsePluginList(Data()) == nil)
}

@Test func prefersTheAppPlugin() {
    let repo = ClaudeCode.InstalledPlugin(id: ClaudeCode.repoPluginID, version: "1", enabled: true, installPath: nil)
    let app = ClaudeCode.InstalledPlugin(id: ClaudeCode.appPluginID, version: "2", enabled: true, installPath: nil)
    let other = ClaudeCode.InstalledPlugin(id: "x@y", version: "3", enabled: true, installPath: nil)
    #expect(ClaudeCode.mooringPlugin(in: [other, repo, app]) == app)
    #expect(ClaudeCode.mooringPlugin(in: [other, repo]) == repo)
    #expect(ClaudeCode.mooringPlugin(in: [other]) == nil)
    #expect(ClaudeCode.appPluginID == "mooring@mooring-app")
    #expect(ClaudeCode.repoPluginID == "mooring@mooring")
    #expect(ClaudeCode.candidatePaths == ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"])
}

@Test func parsesMarketplaces() {
    let json = #"[{"name":"mooring-app","source":"directory","path":"/x"},{"name":"claude-plugins-official","source":"github"}]"#
    #expect(ClaudeCode.parseMarketplaces(Data(json.utf8)) == [
        ClaudeCode.Marketplace(name: "mooring-app", path: "/x"),
        ClaudeCode.Marketplace(name: "claude-plugins-official", path: nil)
    ])
    #expect(ClaudeCode.parseMarketplaces(Data("[]".utf8)) == [])
    #expect(ClaudeCode.parseMarketplaces(Data(#"[{"source":"x"},{"name":"a"}]"#.utf8)) == [ClaudeCode.Marketplace(name: "a", path: nil)])
    #expect(ClaudeCode.parseMarketplaces(Data("nope".utf8)) == nil)
    #expect(ClaudeCode.parseMarketplaces(Data()) == nil)
}

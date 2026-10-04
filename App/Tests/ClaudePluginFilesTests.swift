import Foundation
import Testing

/// File and JSON checks on the Claude Code plugin and its two marketplaces. The behaviour of
/// `mooring-hook` itself is covered by scripts/test-mooring-hook.sh.
struct ClaudePluginFilesTests {
    /// The repo root: App/Tests/<this file> is two levels below it.
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private var plugin: URL { root.appendingPathComponent("Integrations/claude-code-plugin") }

    private func json(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func marketingVersion() throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent("Config/Shared.xcconfig"), encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first { $0.hasPrefix("MARKETING_VERSION") })
        let value = try #require(line.split(separator: "=").last)
        return value.trimmingCharacters(in: .whitespaces)
    }

    @Test func pluginJSONIsValid() throws {
        let manifest = try json(plugin.appendingPathComponent(".claude-plugin/plugin.json"))
        #expect(manifest["name"] as? String == "mooring")
        #expect((manifest["version"] as? String)?.isEmpty == false)
        #expect((manifest["description"] as? String)?.isEmpty == false)
        #expect(manifest["license"] as? String == "GPL-3.0-only")
    }

    // The plugin's version changes only when its files do, so it may trail the app's version but never lead it.
    @Test func pluginVersionMatchesMarketingVersion() throws {
        let manifest = try json(plugin.appendingPathComponent(".claude-plugin/plugin.json"))
        let pluginVersion = try #require(manifest["version"] as? String)
        let marketing = try marketingVersion()
        #expect(pluginVersion.compare(marketing, options: .numeric) != .orderedDescending)
    }

    @Test func hooksReferenceOnlyTheScript() throws {
        let file = try json(plugin.appendingPathComponent("hooks/hooks.json"))
        let hooks = try #require(file["hooks"] as? [String: [[String: Any]]])
        let background: Set<String> = ["PreToolUse", "PostToolUse", "PostToolBatch",
                                       "SubagentStart", "SubagentStop", "PreCompact"]
        let synchronous: Set<String> = ["UserPromptSubmit", "Stop", "StopFailure", "Notification", "PermissionRequest"]
        #expect(Set(hooks.keys) == background.union(synchronous).union(["SessionEnd"]))
        for (event, groups) in hooks {
            #expect(groups.count == 1)
            let entries = try #require(groups.first?["hooks"] as? [[String: Any]])
            #expect(entries.count == 1)
            let entry = try #require(entries.first)
            #expect(entry["type"] as? String == "command")
            #expect(entry["command"] as? String == "\"${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook\" \(event)")
            let timeout = try #require(entry["timeout"] as? Int)
            if background.contains(event) {
                #expect(entry["async"] as? Bool == true)
                #expect(timeout == 5)
            } else {
                #expect(entry["async"] == nil)
                #expect(timeout == (event == "SessionEnd" ? 1 : 2))
            }
        }
    }

    /// Every file under `folder` as a path relative to it, with its bytes. `.DS_Store` is Finder noise and never counts.
    private func contents(of folder: URL) throws -> [String: Data] {
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]))
        var files: [String: Data] = [:]
        for case let url as URL in enumerator {
            guard url.lastPathComponent != ".DS_Store", (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true
            else { continue }
            files[String(url.path.dropFirst(folder.path.count + 1))] = try Data(contentsOf: url)
        }
        return files
    }

    @Test func bundledPluginMatchesTheSource() throws {
        let bundled = try #require(Bundle.main.resourceURL).appendingPathComponent("ClaudePlugin")
        let bundledPlugin = try contents(of: bundled.appendingPathComponent("mooring"))
        let source = try contents(of: plugin)
        #expect(!source.isEmpty)
        #expect(Set(bundledPlugin.keys) == Set(source.keys))
        for (path, data) in source {
            #expect(bundledPlugin[path] == data, "\(path) differs")
        }
        let script = bundled.appendingPathComponent("mooring/scripts/mooring-hook").path
        #expect(FileManager.default.isExecutableFile(atPath: script))
        let marketplace = try Data(contentsOf: bundled.appendingPathComponent(".claude-plugin/marketplace.json"))
        #expect(marketplace == (try Data(contentsOf: root.appendingPathComponent("Integrations/app-marketplace.json"))))
    }

    @Test func marketplacesAreValid() throws {
        let repo = try json(root.appendingPathComponent(".claude-plugin/marketplace.json"))
        #expect(repo["name"] as? String == "mooring")
        let repoPlugin = try #require((repo["plugins"] as? [[String: Any]])?.first)
        #expect(repoPlugin["name"] as? String == "mooring")
        let source = try #require(repoPlugin["source"] as? String)
        #expect(source == "./Integrations/claude-code-plugin")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(source).path))

        let template = try json(root.appendingPathComponent("Integrations/app-marketplace.json"))
        #expect(template["name"] as? String == "mooring-app")
        let bundled = try #require((template["plugins"] as? [[String: Any]])?.first)
        #expect(bundled["name"] as? String == "mooring")
        #expect(bundled["source"] as? String == "./mooring")
    }

    @Test func skillHasFrontmatter() throws {
        let text = try String(contentsOf: plugin.appendingPathComponent("skills/mooring/SKILL.md"), encoding: .utf8)
        let parts = text.components(separatedBy: "---\n")
        #expect(text.hasPrefix("---\n"))
        #expect(parts.count >= 3)
        let frontmatter = parts.count > 1 ? parts[1] : ""
        #expect(frontmatter.contains("name: mooring\n"))
        #expect(frontmatter.contains("description: "))
        #expect(text.contains("mooring anchor --reason"))
        #expect(text.contains("mooring lease release job-"))
    }

    @Test func scriptIsExecutable() {
        let script = plugin.appendingPathComponent("scripts/mooring-hook")
        #expect(FileManager.default.isExecutableFile(atPath: script.path))
    }

    @Test func mooringJSONHasTestedWith() throws {
        let file = try json(plugin.appendingPathComponent("mooring.json"))
        let tested = try #require(file["testedWithClaudeCode"] as? String)
        #expect(tested.split(separator: ".").count == 2)
    }
}

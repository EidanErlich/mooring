import Foundation
import MooringIPC
import Testing
@testable import Mooring

/// No agent path (socket, CLI, MCP, links, Shortcuts, AppleScript) can reach clipboard history. The MCP tool list is
/// checked in MooringCLICoreTests, which owns the MCP server.
struct AgentWallTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func swiftFiles(under folders: [String]) -> [URL] {
        folders.flatMap { folder -> [URL] in
            let base = root.appendingPathComponent(folder)
            let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
            return (walker?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        }
    }

    /// Each `file: needle` where a source file under `folders` contains one of `needles`.
    private static func hits(of needles: [String], under folders: [String]) throws -> [String] {
        var found: [String] = []
        for file in swiftFiles(under: folders) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for needle in needles where text.contains(needle) {
                found.append("\(file.path.replacingOccurrences(of: root.path + "/", with: "")): \(needle)")
            }
        }
        return found.sorted()
    }

    @Test func agentPathsDontImportClipKit() throws {
        let folders = ["App/IPC", "App/Links", "App/Intents", "Packages/MooringIPC/Sources"]
        #expect(Self.swiftFiles(under: folders).count > 20, "the scan found the agent folders")
        let needles = [
            "import ClipKit", "ClipKit.", "HistoryItem", "Clipboard.shared", "Storage.shared", "ClipboardController", "NSPasteboard"
        ]
        #expect(try Self.hits(of: needles, under: folders).isEmpty)
    }

    @Test func noClipboardOps() throws {
        let pattern = try Regex("clip|paste|history").ignoresCase()
        #expect(!Op.allCases.isEmpty)
        for operation in Op.allCases {
            #expect(operation.rawValue.firstMatch(of: pattern) == nil, "\(operation.rawValue) names the clipboard")
        }
    }

    @Test func noAppIntentsInClipKit() throws {
        let folder = "Packages/ClipKit/Sources"
        #expect(Self.swiftFiles(under: [folder]).count > 20, "the scan found ClipKit")
        #expect(try Self.hits(of: ["AppIntent", "AppEntity", "AppShortcutsProvider"], under: [folder]).isEmpty)
    }

    @Test func appleScriptDisabled() throws {
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSAppleScriptEnabled") as? Bool == false)
        let walker = FileManager.default.enumerator(at: Self.root.appendingPathComponent("App"), includingPropertiesForKeys: nil)
        let scriptingDefinitions = (walker?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "sdef" }
        #expect(scriptingDefinitions.isEmpty)
        #expect(Bundle.main.url(forResource: "Mooring", withExtension: "sdef") == nil)
    }

    @Test func linksHaveNoClipboardRoutes() throws {
        for name in ["clipboard", "paste", "history"] {
            let url = try #require(URL(string: "mooring://\(name)"))
            guard case .failure = MooringLink.parse(url) else {
                Issue.record("mooring://\(name) parsed")
                continue
            }
        }
    }
}

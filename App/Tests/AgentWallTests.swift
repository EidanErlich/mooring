import Foundation
import MooringIPC
import Testing
@testable import Mooring

/// No agent path (socket, CLI, MCP, links, Shortcuts, AppleScript) can reach clipboard history. The MCP tool list is
/// checked in MooringCLICoreTests, which owns the MCP server.
struct AgentWallTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let agentFolders = ["App/IPC", "App/Links", "App/Intents", "Packages/MooringIPC/Sources"]

    private static func swiftFiles(under folders: [String]) -> [URL] {
        folders.flatMap { folder -> [URL] in
            let base = root.appendingPathComponent(folder)
            let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
            return (walker?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        }
    }

    /// Each folder must exist and hold Swift files, so a moved folder can't leave a scan passing on nothing.
    private static func expectEachFolderHasSources(_ folders: [String]) {
        for folder in folders {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: root.appendingPathComponent(folder).path, isDirectory: &isDirectory)
            #expect(exists && isDirectory.boolValue, "\(folder) exists")
            #expect(!swiftFiles(under: [folder]).isEmpty, "\(folder) has Swift files")
        }
    }

    private static func relative(_ file: URL) -> String {
        file.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    /// Each `file: pattern` where a source file under `folders` matches one of the regular expressions `patterns`.
    private static func hits(of patterns: [String], under folders: [String]) throws -> [String] {
        let regexes = try patterns.map { ($0, try Regex($0)) }
        var found: [String] = []
        for file in swiftFiles(under: folders) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (pattern, regex) in regexes where text.firstMatch(of: regex) != nil {
                found.append("\(relative(file)): \(pattern)")
            }
        }
        return found.sorted()
    }

    @Test func agentPathsDontImportClipKit() throws {
        Self.expectEachFolderHasSources(Self.agentFolders)
        let patterns = [
            #"\bClipKit\b"#, "HistoryItem", #"Clipboard\.shared"#, #"Storage\.shared"#, "ClipboardController", "NSPasteboard"
        ]
        #expect(try Self.hits(of: patterns, under: Self.agentFolders).isEmpty)
    }

    /// Catches a neutral-named closure or string, such as a `clipboardPeek:` parameter, that the specific names miss.
    @Test func agentPathsNameNoClipboardConcept() throws {
        Self.expectEachFolderHasSources(Self.agentFolders)
        #expect(try Self.hits(of: ["(?i)clipboard|pasteboard|history"], under: Self.agentFolders).isEmpty)
    }

    @Test func agentManifestDoesntMentionClipKit() throws {
        let manifest = try String(contentsOf: Self.root.appendingPathComponent("Packages/MooringIPC/Package.swift"), encoding: .utf8)
        #expect(manifest.contains("MooringIPC"))
        #expect(!manifest.contains("ClipKit"))
    }

    /// A new folder under App/ must be classified: an agent path (add it to `agentFolders`) or not (add it here).
    @Test func appFoldersAreAllClassified() throws {
        let appFolder = Self.root.appendingPathComponent("App")
        let entries = try FileManager.default.contentsOfDirectory(at: appFolder, includingPropertiesForKeys: [.isDirectoryKey])
        let folders = try entries.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
            .map(\.lastPathComponent).sorted()
        #expect(folders == [
            "Assets.xcassets", "Clipboard", "Helper", "IPC", "Icon", "Intents", "Links", "Settings", "Sources", "Tests", "UI", "Windows"
        ])
    }

    @Test func requestHandlerIsGivenNoClipboardArgument() throws {
        let file = Self.root.appendingPathComponent("App/Sources/AppDelegate.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        var blocks: [Substring] = []
        var search = text.startIndex..<text.endIndex
        while let call = text.range(of: "RequestHandler(", range: search) {
            var depth = 1
            var index = call.upperBound
            while index < text.endIndex, depth > 0 {
                if text[index] == "(" { depth += 1 } else if text[index] == ")" { depth -= 1 }
                index = text.index(after: index)
            }
            blocks.append(text[call.upperBound..<index])
            search = index..<text.endIndex
        }
        #expect(!blocks.isEmpty, "found the RequestHandler initialiser")
        for block in blocks {
            #expect(block.range(of: "clipboard", options: .caseInsensitive) == nil)
        }
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
        Self.expectEachFolderHasSources([folder])
        #expect(try Self.hits(of: ["AppIntent", "AppEntity", "AppShortcutsProvider"], under: [folder]).isEmpty)
    }

    @Test func appleScriptDisabled() throws {
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSAppleScriptEnabled") as? Bool == false)
        #expect(FileManager.default.fileExists(atPath: Self.root.appendingPathComponent("App/Info.plist").path))
        let walker = FileManager.default.enumerator(at: Self.root.appendingPathComponent("App"), includingPropertiesForKeys: nil)
        let scriptingDefinitions = (walker?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "sdef" }
        #expect(scriptingDefinitions.isEmpty)
        #expect(Bundle.main.urls(forResourcesWithExtension: "sdef", subdirectory: nil)?.isEmpty ?? true)
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

import Foundation
import MooringIPC
import Testing
@testable import Mooring

@MainActor
struct MCPClientsModelTests {
    nonisolated private static let helperPath = "/Applications/Mooring.app/Contents/Helpers/mooring"

    private final class Copies {
        var texts: [String] = []
    }

    @MainActor private struct Fixture {
        let home: URL
        let copies = Copies()
        let model: MCPClientsModel

        init(installed: [MCPClientConfig.Client] = MCPClientConfig.Client.allCases) throws {
            home = FileManager.default.temporaryDirectory.appendingPathComponent("mooring-mcp-\(UUID().uuidString)")
            for client in installed {
                try FileManager.default.createDirectory(
                    at: MCPClientConfig(client: client, home: home).folderURL, withIntermediateDirectories: true
                )
            }
            let copies = copies
            model = MCPClientsModel(home: home, helperPath: MCPClientsModelTests.helperPath) { copies.texts.append($0) }
        }

        func config(_ client: MCPClientConfig.Client) -> MCPClientConfig {
            MCPClientConfig(client: client, home: home)
        }
    }

    @Test func rowsReflectStates() throws {
        let fixture = try Fixture(installed: [.claudeDesktop])
        try fixture.config(.claudeDesktop).add(helperPath: Self.helperPath)
        fixture.model.refresh()
        #expect(fixture.model.rows.map(\.client) == [.claudeDesktop, .cursor])
        #expect(fixture.model.rows.map(\.state) == [.added, .notInstalled])
        #expect(fixture.model.rows.map(\.buttonTitle) == ["Remove", nil])
        #expect(fixture.model.rows.map(\.name) == ["Claude Desktop", "Cursor"])
    }

    @Test func buttonTitlesFollowState() {
        func title(_ state: MCPClientConfig.State) -> String? {
            MCPClientsModel.Row(client: .cursor, state: state, message: nil).buttonTitle
        }
        #expect(title(.notInstalled) == nil)
        #expect(title(.notAdded) == "Add")
        #expect(title(.added) == "Remove")
        #expect(title(.needsUpdate("/old/mooring")) == "Update")
    }

    @Test func addThenRowIsAddedWithRestartMessage() throws {
        let fixture = try Fixture()
        fixture.model.refresh()
        #expect(fixture.model.rows[0].state == .notAdded)
        fixture.model.perform(.claudeDesktop)
        #expect(fixture.model.rows[0].state == .added)
        #expect(fixture.model.rows[0].message == "Restart Claude Desktop to load it.")
        #expect(fixture.model.rows[1].message == nil)
    }

    @Test func updateRepointsAStaleEntry() throws {
        let fixture = try Fixture()
        try fixture.config(.cursor).add(helperPath: "/old/mooring")
        fixture.model.refresh()
        #expect(fixture.model.rows[1].buttonTitle == "Update")
        fixture.model.perform(.cursor)
        #expect(fixture.model.rows[1].state == .added)
        #expect(fixture.model.rows[1].message == "Restart Cursor to load it.")
    }

    @Test func invalidJSONShowsMessageAndLeavesFile() throws {
        let fixture = try Fixture()
        let file = fixture.config(.claudeDesktop).fileURL
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)
        fixture.model.refresh()
        fixture.model.perform(.claudeDesktop)
        #expect(fixture.model.rows[0].message
            == "\(file.path) isn't valid JSON, so Mooring left it alone. Use Copy config instead.")
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ not json")
    }

    @Test func removeReturnsToNotAdded() throws {
        let fixture = try Fixture()
        try fixture.config(.cursor).add(helperPath: Self.helperPath)
        fixture.model.refresh()
        #expect(fixture.model.rows[1].state == .added)
        fixture.model.perform(.cursor)
        #expect(fixture.model.rows[1].state == .notAdded)
        #expect(fixture.model.rows[1].message == nil)
    }

    @Test func copyConfigCopiesSnippet() throws {
        let fixture = try Fixture()
        fixture.model.copyConfig()
        #expect(fixture.copies.texts == [MCPClientConfig.snippet(helperPath: Self.helperPath)])
    }

    @Test func helperPathPointsIntoTheBundle() {
        #expect(MCPClientsModel.bundledHelperPath(in: URL(fileURLWithPath: "/Applications/Mooring.app"))
            == "/Applications/Mooring.app/Contents/Helpers/mooring")
    }
}

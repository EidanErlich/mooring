import AwakeKit
import Testing
@testable import Mooring

struct AgentsSettingsTests {
    @Test func lidApprovalLabels() {
        #expect(AgentLidApproval.allCases.map(AgentsSettingsPage.label(for:))
            == ["Ask only when it has no end", "Always ask", "Always allow", "Never"])
    }

    @Test func windowArrangementModes() {
        #expect(AgentsSettingsPage.windowModes.map(AgentsSettingsPage.label(for:)) == ["Automatic", "Ask first", "Off"])
        #expect(AgentsSettingsPage.windowsCaption
            == "Agents can move and resize your windows with `mooring win` and MCP. Windows must be on.")
    }
}

import AwakeKit
import Testing
@testable import Mooring

struct AgentsSettingsTests {
    @Test func lidApprovalLabels() {
        #expect(AgentLidApproval.allCases.map(AgentsSettingsPage.label(for:))
            == ["Ask only when it has no end", "Always ask", "Always allow", "Never"])
    }
}

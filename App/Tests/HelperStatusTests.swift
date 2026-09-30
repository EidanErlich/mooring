import ServiceManagement
import Testing
@testable import Mooring

struct HelperStatusTests {
    @Test(arguments: [
        (SMAppService.Status.notRegistered, HelperStatus.notRegistered),
        (.requiresApproval, .requiresApproval),
        (.enabled, .enabled),
        (.notFound, .notFound)
    ])
    func mapsServiceManagementStatus(_ input: SMAppService.Status, _ expected: HelperStatus) {
        #expect(HelperStatus(input) == expected)
    }
}

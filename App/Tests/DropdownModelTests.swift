import AwakeKit
import Foundation
import Testing
@testable import Mooring

@MainActor
struct DropdownModelTests {
    @Test func closingClearsHighlightAndStopsTimelines() {
        let model = DropdownModel()
        model.menuDidOpen()
        #expect(model.isOpen)
        model.highlightedID = "duration.hour1"
        model.menuDidClose()
        #expect(!model.isOpen)
        #expect(model.highlightedID == nil)
    }
}

private let start = Date(timeIntervalSince1970: 1_000_000)

private func menuLease(expiresAt: Date?) -> Lease {
    Lease(id: "menu", owner: .menu, reason: "r", level: .system, expiresAt: expiresAt, createdAt: start)
}

struct DurationCheckTests {
    @Test func currentPickIsChecked() {
        let expiry = start.addingTimeInterval(7200)
        let pick = DurationPick(duration: .hours2, expiresAt: expiry)
        #expect(pick.isChecked(.hours2, menuLease: menuLease(expiresAt: expiry)) == true)
        #expect(pick.isChecked(.hour1, menuLease: menuLease(expiresAt: expiry)) == false)
    }

    @Test func staleTimedPickDoesNotMarkUntilTurnedOffLease() {
        let pick = DurationPick(duration: .hour1, expiresAt: start.addingTimeInterval(3600))
        let lease = menuLease(expiresAt: nil)
        #expect(pick.isChecked(.hour1, menuLease: lease) == false)
        #expect(pick.isChecked(.untilTurnedOff, menuLease: lease) == true)
    }

    @Test func leaseRenewedElsewhereClearsTheCheck() {
        let pick = DurationPick(duration: .hour1, expiresAt: start.addingTimeInterval(3600))
        let lease = menuLease(expiresAt: start.addingTimeInterval(9000))
        #expect(AwakeDuration.allCases.allSatisfy { !pick.isChecked($0, menuLease: lease) })
    }

    @Test func noMenuLeaseChecksNothing() {
        let pick = DurationPick(duration: .hour1, expiresAt: nil)
        #expect(AwakeDuration.allCases.allSatisfy { !pick.isChecked($0, menuLease: nil) })
        #expect(!DurationPick.none.isChecked(.untilTurnedOff, menuLease: nil))
    }
}

import AwakeKit
import Foundation
import Testing
@testable import Mooring

/// A Deny holds for `LidMessage.denialLasts`, then the agent may ask again.
@MainActor
struct RequestHandlerLidDenialTests {
    @Test func denialLastsFifteenMinutes() async throws {
        let fixture = RequestFixture.agent()
        fixture.approver.answers = [.deny, .allowOnce]

        _ = await fixture.acquire(.on, level: "lid")
        fixture.knobs.clock.addTimeInterval(15 * 60 - 1)
        let stillDenied = await fixture.acquire(.on, level: "lid")
        #expect(wireFailure(stillDenied)?.code == .denied)
        #expect(fixture.approver.calls.count == 1)

        fixture.knobs.clock.addTimeInterval(1)
        let askedAgain = await fixture.acquire(.on, level: "lid")
        #expect(askedAgain.ok)
        #expect(fixture.approver.calls.count == 2)
        #expect(try #require(fixture.lease("menu")).level == lidOnly)
    }

    @Test func deniedUntilNamesTheTime() {
        let until = Date(timeIntervalSince1970: 1_000_000)
        let time = until.formatted(date: .omitted, time: .shortened)
        #expect(LidMessage.deniedUntil(until) == "Lid mode not approved (you denied it; ask again after \(time))")
    }
}

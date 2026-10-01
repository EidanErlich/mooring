import AwaykeMonitors
import Testing

// Ported from Awayke@b502251: Tests/main.swift.
struct LidSessionTrackerTests {
    @Test func openStartWaitsForCloseThenExpiresOnOpen() {
        let tracker = LidSessionTracker()
        tracker.start(lidClosed: false)
        #expect(tracker.isWaitingForClose)
        #expect(tracker.handle(lidClosed: false) == false)
        #expect(tracker.handle(lidClosed: true) == false)
        #expect(!tracker.isWaitingForClose)
        #expect(tracker.handle(lidClosed: false) == true)
        #expect(tracker.handle(lidClosed: false) == false)
    }

    @Test func closedStartExpiresOnOpen() {
        let tracker = LidSessionTracker()
        tracker.start(lidClosed: true)
        #expect(tracker.handle(lidClosed: false) == true)
    }

    @Test func cancelledSessionIgnoresEvents() {
        let tracker = LidSessionTracker()
        tracker.start(lidClosed: false)
        tracker.cancel()
        #expect(tracker.handle(lidClosed: true) == false)
        #expect(tracker.handle(lidClosed: false) == false)
    }

    @Test func unknownStartWaitsForFullCycle() {
        let tracker = LidSessionTracker()
        tracker.start(lidClosed: nil)
        #expect(tracker.isWaitingForClose)
        #expect(tracker.handle(lidClosed: true) == false)
        #expect(tracker.handle(lidClosed: false) == true)
    }
}

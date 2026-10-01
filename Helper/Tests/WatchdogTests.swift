import Foundation
import Testing

private let start = Date(timeIntervalSince1970: 0)

private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

struct WatchdogTests {
    @Test func timingsAreSnappy() {
        #expect(Watchdog.reconnectGrace == 3)
        #expect(Watchdog.checkInterval == 1)
        #expect(Watchdog.heartbeatTimeout == 90)
    }

    @Test func idleWatchdogNeverRestores() {
        #expect(!Watchdog().shouldRestore(at: at(1000)))
    }

    /// A crashed app is never back within 3 s; it re-applies lid mode itself if it relaunches.
    @Test func restoresThreeSecondsAfterLastConnectionCloses() {
        var watchdog = Watchdog()
        watchdog.connectionOpened()
        watchdog.didSetSleepDisabled(true, at: start)
        watchdog.connectionClosed(at: at(5))
        #expect(!watchdog.shouldRestore(at: at(7.9)))
        #expect(watchdog.shouldRestore(at: at(8)))
    }

    @Test func reconnectWithinGraceCancelsRestore() {
        var watchdog = Watchdog()
        watchdog.connectionOpened()
        watchdog.didSetSleepDisabled(true, at: start)
        watchdog.connectionClosed(at: at(5))
        watchdog.connectionOpened()
        watchdog.didHeartbeat(at: at(7), sleepDisabled: true)
        #expect(!watchdog.shouldRestore(at: at(20)))
    }

    @Test func staleHeartbeatRestoresEvenWithOpenConnection() {
        var watchdog = Watchdog()
        watchdog.connectionOpened()
        watchdog.didSetSleepDisabled(true, at: start)
        watchdog.didHeartbeat(at: at(30), sleepDisabled: true)
        #expect(!watchdog.shouldRestore(at: at(119)))
        #expect(watchdog.shouldRestore(at: at(120)))
    }

    @Test func onlyRestoresSleepItDisabled() {
        var watchdog = Watchdog()
        watchdog.connectionOpened()
        watchdog.connectionClosed(at: start)
        #expect(!watchdog.shouldRestore(at: at(100)))
        watchdog.connectionOpened()
        watchdog.didSetSleepDisabled(true, at: start)
        watchdog.didSetSleepDisabled(false, at: at(1))
        watchdog.connectionClosed(at: at(2))
        #expect(!watchdog.shouldRestore(at: at(100)))
    }

    @Test func didRestoreStopsFurtherRestores() {
        var watchdog = Watchdog()
        watchdog.connectionOpened()
        watchdog.didSetSleepDisabled(true, at: start)
        watchdog.connectionClosed(at: start)
        watchdog.didRestore()
        #expect(!watchdog.sleepDisabledByUs)
        #expect(!watchdog.shouldRestore(at: at(10_000)))
    }

    @Test func twoConnectionsNeedBothClosed() {
        var watchdog = Watchdog()
        watchdog.connectionOpened()
        watchdog.connectionOpened()
        watchdog.didSetSleepDisabled(true, at: start)
        watchdog.connectionClosed(at: start)
        watchdog.didHeartbeat(at: at(60), sleepDisabled: true)
        #expect(!watchdog.shouldRestore(at: at(60)))
    }

    /// A helper that restarted (crash, kickstart) finds SleepDisabled = 1 it no longer
    /// knows it set. The app's heartbeat hands ownership back, so a later kill still restores.
    @Test func heartbeatSeeingDisabledSleepAdoptsOwnership() {
        var watchdog = Watchdog()
        watchdog.connectionOpened()
        watchdog.didHeartbeat(at: start, sleepDisabled: true)
        #expect(watchdog.sleepDisabledByUs)
        watchdog.connectionClosed(at: start)
        #expect(!watchdog.shouldRestore(at: at(2.9)))
        #expect(watchdog.shouldRestore(at: at(3)))
    }

    @Test func heartbeatSeeingEnabledSleepAdoptsNothing() {
        var watchdog = Watchdog()
        watchdog.connectionOpened()
        watchdog.didHeartbeat(at: start, sleepDisabled: false)
        watchdog.connectionClosed(at: start)
        #expect(!watchdog.shouldRestore(at: at(100)))
    }

    /// At boot or restart with the ownership marker present and SleepDisabled still 1,
    /// the helper treats the app as gone until it reconnects.
    @Test func startingWhileOwningRestoresAfterGraceUnlessAppReconnects() {
        var owning = Watchdog()
        owning.didStart(owningSleep: true, at: start)
        #expect(!owning.shouldRestore(at: at(2.9)))
        #expect(owning.shouldRestore(at: at(3)))

        var reconnected = Watchdog()
        reconnected.didStart(owningSleep: true, at: start)
        reconnected.connectionOpened()
        reconnected.didHeartbeat(at: at(2), sleepDisabled: true)
        #expect(!reconnected.shouldRestore(at: at(30)))

        var notOwning = Watchdog()
        notOwning.didStart(owningSleep: false, at: start)
        #expect(!notOwning.shouldRestore(at: at(1000)))
    }
}

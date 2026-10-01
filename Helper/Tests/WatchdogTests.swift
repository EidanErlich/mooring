import Foundation
import Testing

private let start = Date(timeIntervalSince1970: 0)

private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

struct WatchdogTests {
    @Test func idleWatchdogNeverRestores() {
        #expect(!Watchdog().shouldRestore(at: at(1000)))
    }

    @Test func restoresTenSecondsAfterLastConnectionCloses() {
        var watchdog = Watchdog()
        watchdog.connectionOpened()
        watchdog.didSetSleepDisabled(true, at: start)
        watchdog.connectionClosed(at: at(5))
        #expect(!watchdog.shouldRestore(at: at(14)))
        #expect(watchdog.shouldRestore(at: at(15)))
    }

    @Test func reconnectWithinGraceCancelsRestore() {
        var watchdog = Watchdog()
        watchdog.connectionOpened()
        watchdog.didSetSleepDisabled(true, at: start)
        watchdog.connectionClosed(at: at(5))
        watchdog.connectionOpened()
        watchdog.didHeartbeat(at: at(8))
        #expect(!watchdog.shouldRestore(at: at(20)))
    }

    @Test func staleHeartbeatRestoresEvenWithOpenConnection() {
        var watchdog = Watchdog()
        watchdog.connectionOpened()
        watchdog.didSetSleepDisabled(true, at: start)
        watchdog.didHeartbeat(at: at(30))
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
        watchdog.didHeartbeat(at: at(60))
        #expect(!watchdog.shouldRestore(at: at(60)))
    }
}

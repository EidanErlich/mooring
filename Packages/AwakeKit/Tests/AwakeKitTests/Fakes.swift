import AwakeKit
import Foundation

@MainActor
final class FakeWatch: ProcessWatch {
    let pid: Int32
    private weak var owner: FakeProcesses?

    init(pid: Int32, owner: FakeProcesses) {
        self.pid = pid
        self.owner = owner
    }

    func cancel() {
        owner?.cancelled.append(pid)
        owner?.handlers[pid] = nil
    }
}

/// Processes whose start times the test sets, and whose exits the test triggers.
@MainActor
final class FakeProcesses: ProcessInspecting {
    var startTimes: [Int32: Date] = [:]
    var handlers: [Int32: @MainActor () -> Void] = [:]
    var cancelled: [Int32] = []

    func startTime(of pid: Int32) -> Date? { startTimes[pid] }

    func watchExit(of pid: Int32, onExit: @escaping @MainActor () -> Void) -> any ProcessWatch {
        handlers[pid] = onExit
        return FakeWatch(pid: pid, owner: self)
    }

    func exit(_ pid: Int32) {
        startTimes[pid] = nil
        handlers.removeValue(forKey: pid)?()
    }
}

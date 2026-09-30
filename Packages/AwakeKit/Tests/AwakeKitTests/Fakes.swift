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

struct Applied: Equatable {
    let system: Bool
    let display: Bool
}

@MainActor
final class RecordingAssertions: AssertionApplying {
    var calls: [Applied] = []

    func apply(system: Bool, display: Bool) {
        calls.append(Applied(system: system, display: display))
    }
}

@MainActor
final class MemoryLeaseStore: LeaseStoring {
    var toLoad: [Lease] = []
    var saved: [Lease] = []
    var saveCount = 0

    func load() -> [Lease] { toLoad }

    func save(_ leases: [Lease]) {
        saved = leases
        saveCount += 1
    }
}

/// An engine wired to fakes, with a clock and settings the test controls.
@MainActor
final class EngineHarness {
    var clock = Date(timeIntervalSince1970: 1_000_000)
    var settings = AwakeSettings()
    let assertions = RecordingAssertions()
    let store = MemoryLeaseStore()
    let processes = FakeProcesses()
    private(set) lazy var engine = AwakeEngine(
        assertions: assertions, store: store, processes: processes,
        settings: { [unowned self] in self.settings }, now: { [unowned self] in self.clock }
    )

    func advance(_ seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
    }
}

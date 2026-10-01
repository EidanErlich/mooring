import AwakeKit
import Foundation
@testable import Mooring

/// A helper whose SleepDisabled the test controls.
@MainActor
final class FakeLidHelper: LidHelper {
    var status = HelperStatus.enabled
    var sleepDisabled = false
    var failNextSet = false
    var calls: [String] = []

    init(sleepDisabled: Bool = false) {
        self.sleepDisabled = sleepDisabled
    }

    func setLidSleepDisabled(_ disabled: Bool) async throws {
        calls.append("set \(disabled)")
        if failNextSet {
            failNextSet = false
            throw HelperClientError.remote("refused")
        }
        sleepDisabled = disabled
    }

    func lidSleepDisabled() async throws -> Bool {
        calls.append("read")
        return sleepDisabled
    }

    func heartbeat() async throws -> Bool {
        calls.append("heartbeat")
        return sleepDisabled
    }

    func unregister() async throws {
        calls.append("unregister")
        status = .notRegistered
    }
}

/// A helper that refuses everything instantly (a signing mismatch, a broken pmset).
@MainActor
final class BrokenLidHelper: LidHelper {
    var status = HelperStatus.enabled
    var calls = 0
    func setLidSleepDisabled(_ disabled: Bool) async throws { calls += 1; throw HelperClientError.remote("no") }
    func lidSleepDisabled() async throws -> Bool { calls += 1; throw HelperClientError.remote("no") }
    func heartbeat() async throws -> Bool { calls += 1; throw HelperClientError.remote("no") }
    func unregister() async throws {}
}

// Minimal engine dependencies for app tests (AwakeKit's own fakes live in its test target).
@MainActor
final class NullAssertions: AssertionApplying {
    func apply(system: Bool, display: Bool) -> HeldAssertions { HeldAssertions(system: system, display: display) }
}

@MainActor
final class MemoryStore: LeaseStoring {
    var leases: [Lease] = []
    func load() -> [Lease] { leases }
    func save(_ leases: [Lease]) { self.leases = leases }
}

@MainActor
final class NoProcesses: ProcessInspecting {
    private final class Watch: ProcessWatch { func cancel() {} }
    func startTime(of pid: Int32) -> Date? { nil }
    func watchExit(of pid: Int32, onExit: @escaping @MainActor () -> Void) -> any ProcessWatch { Watch() }
}

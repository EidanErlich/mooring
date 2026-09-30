import AwakeKit
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_000_000)

private func lease(_ id: String, expiresAt: Date? = nil, watch: WatchedProcess? = nil) -> Lease {
    Lease(id: id, owner: .menu, reason: "r", level: .system, expiresAt: expiresAt, watch: watch, createdAt: now)
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "mooring-tests-\(UUID().uuidString)/Mooring")
}

private func permissions(_ url: URL) throws -> Int {
    try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
}

@MainActor
struct LeaseStoreTests {
    @Test func saveThenLoadRoundTrips() {
        let store = FileLeaseStore(directory: tempDirectory())
        let leases = [lease("menu", expiresAt: now.addingTimeInterval(60)), lease("app-4", watch: .init(pid: 4, startTime: now))]
        store.save(leases)
        #expect(store.load() == leases)
    }

    @Test func fileIsOwnerOnly() throws {
        let directory = tempDirectory()
        let store = FileLeaseStore(directory: directory)
        store.save([lease("menu")])
        #expect(try permissions(store.fileURL) == 0o600)
        #expect(try permissions(directory) == 0o700)
    }

    @Test func missingFileLoadsEmpty() {
        #expect(FileLeaseStore(directory: tempDirectory()).load() == [])
    }

    @Test func corruptFileLoadsEmpty() throws {
        let directory = tempDirectory()
        let store = FileLeaseStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.fileURL)
        #expect(store.load() == [])
        store.save([lease("menu")])
        #expect(store.load() == [lease("menu")])
    }

    @Test func restorableKeepsInDateLeases() {
        let leases = [lease("a"), lease("b", expiresAt: now.addingTimeInterval(60)), lease("c", expiresAt: now.addingTimeInterval(-1))]
        let kept = LeaseRestore.restorable(leases, now: now, processes: FakeProcesses())
        #expect(kept.map(\.id) == ["a", "b"])
    }

    @Test func restorableDropsDeadWatchedProcess() {
        let leases = [lease("app-9", watch: .init(pid: 9, startTime: now))]
        #expect(LeaseRestore.restorable(leases, now: now, processes: FakeProcesses()).isEmpty)
    }

    @Test func restorableDropsReusedPID() {
        let started = now.addingTimeInterval(-600)
        let leases = [lease("app-9", watch: .init(pid: 9, startTime: started))]
        let processes = FakeProcesses()
        processes.startTimes[9] = started.addingTimeInterval(30)
        #expect(LeaseRestore.restorable(leases, now: now, processes: processes).isEmpty)
        processes.startTimes[9] = started.addingTimeInterval(0.5)
        #expect(LeaseRestore.restorable(leases, now: now, processes: processes).map(\.id) == ["app-9"])
    }
}

import Foundation

/// Where the handler's record of lid mode got on an agent's behalf (`RequestHandler.agentLid`) lives between launches:
/// lease id → the lease's `createdAt`, as seconds since 1970. The app keeps it in its defaults, under `agentLidGrants`.
@MainActor
final class AgentLidRecord {
    /// How far a saved creation time may differ from the restored lease's and still name the same lease: the lease
    /// table and this record store a `Date` in different encodings, which can differ in the last bits.
    static let createdTolerance: TimeInterval = 0.001

    private let read: @MainActor () -> [String: Double]
    private let write: @MainActor ([String: Double]) -> Void

    init(read: @escaping @MainActor () -> [String: Double], write: @escaping @MainActor ([String: Double]) -> Void) {
        self.read = read
        self.write = write
    }

    func load() -> [String: Date] {
        read().mapValues(Date.init(timeIntervalSince1970:))
    }

    func save(_ grants: [String: Date]) {
        write(grants.mapValues(\.timeIntervalSince1970))
    }
}

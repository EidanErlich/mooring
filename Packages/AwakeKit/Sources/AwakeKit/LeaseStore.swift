import Foundation
import os

/// Where the lease table lives between launches (docs/SPEC.md 1.2, Persistence).
@MainActor
public protocol LeaseStoring: AnyObject {
    func load() -> [Lease]
    func save(_ leases: [Lease])
}

/// `leases.json` in a directory only the user can enter (0700), written 0600.
@MainActor
public final class FileLeaseStore: LeaseStoring {
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Mooring", directoryHint: .isDirectory)
    }

    public let directory: URL
    public var fileURL: URL { directory.appending(path: "leases.json") }
    private let log = Logger(subsystem: "dev.mooring", category: "engine")

    public init(directory: URL = FileLeaseStore.defaultDirectory) {
        self.directory = directory
    }

    public func load() -> [Lease] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([Lease].self, from: data)
        } catch {
            log.error("ignoring unreadable leases.json: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func save(_ leases: [Lease]) {
        do {
            let files = FileManager.default
            try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            try encoder.encode(leases).write(to: fileURL, options: .atomic)
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            log.error("saving leases.json failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

public enum LeaseRestore {
    /// How far a watched process's start time may drift and still count as the same process.
    public static let startTimeTolerance: TimeInterval = 1

    /// The leases worth restoring at launch: still in date, and, if they watch a
    /// process, that same process (not a reused PID) is still running.
    @MainActor
    public static func restorable(_ leases: [Lease], now: Date, processes: any ProcessInspecting) -> [Lease] {
        leases.filter { lease in
            guard lease.isLive(at: now) else { return false }
            guard let watch = lease.watch else { return true }
            guard let started = processes.startTime(of: watch.pid) else { return false }
            return abs(started.timeIntervalSince(watch.startTime)) <= startTimeTolerance
        }
    }
}

import Darwin
import Foundation
import os
import Testing
@testable import Mooring

/// `SocketServerTests` continued: backing off `accept` while out of file descriptors.
extension SocketServerTests {
    /// Out of descriptors, the pending connection stays queued: the listener waits 100 ms instead of spinning on it,
    /// then tries again. Stopping while it waits is safe.
    @Test func acceptBacksOffOnEMFILE() async throws {
        try await withSocketPath { path in
            let calls = OSAllocatedUnfairLock(initialState: 0)
            let server = SocketServer(path: path, accept: { _ in
                calls.withLock { $0 += 1 }
                return (descriptor: -1, error: EMFILE)
            }, handle: Self.released)
            try server.start()
            defer { server.stop() }
            let client = try RawClient.connect(path)
            defer { Darwin.close(client) }

            try await Task.sleep(for: .milliseconds(50))
            let early = calls.withLock { $0 }
            #expect(early >= 1 && early < 5)
            let deadline = Date().addingTimeInterval(2)
            while calls.withLock({ $0 }) < early + 1, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(calls.withLock { $0 } > early)
        }
    }

    /// Running out of descriptors is logged once per episode, not on every retry; an accepted connection ends it.
    @Test func acceptLogsOncePerEpisode() async throws {
        try await withSocketPath { path in
            let failing = OSAllocatedUnfairLock(initialState: true)
            let calls = OSAllocatedUnfairLock(initialState: 0)
            let server = SocketServer(path: path, accept: { listening in
                calls.withLock { $0 += 1 }
                return failing.withLock { $0 } ? (descriptor: -1, error: EMFILE) : SocketServer.liveAccept(listening)
            }, handle: Self.released)
            try server.start()
            defer { server.stop() }
            func waitForCalls(_ count: Int) async throws {
                let deadline = Date().addingTimeInterval(3)
                while calls.withLock({ $0 }) < count, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            }

            let first = try RawClient.connect(path)
            defer { Darwin.close(first) }
            try await waitForCalls(3)
            #expect(server.backOffEpisodes == 1)

            failing.withLock { $0 = false }
            RawClient.send(first, try releaseLine())
            #expect(try await RawClient.offPool { RawClient.receive(first, timeout: 3) }.line != nil)

            failing.withLock { $0 = true }
            let before = calls.withLock { $0 }
            let second = try RawClient.connect(path)
            defer { Darwin.close(second) }
            try await waitForCalls(before + 3)
            #expect(server.backOffEpisodes == 2)
        }
    }
}

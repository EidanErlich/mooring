import Darwin
import Foundation
import MooringIPC
import os
import Testing
@testable import Mooring

struct SocketServerTests {
    static let released: @Sendable (Request, Caller) async -> Response = { request, _ in
        .success(id: request.id, .release(ReleaseResult(released: true)))
    }

    @Test func createsDirectoryAndSocketWithPrivateModes() throws {
        try withSocketPath { path in
            let server = SocketServer(path: path, handle: Self.released)
            try server.start()
            defer { server.stop() }

            #expect(mode(of: (path as NSString).deletingLastPathComponent) == S_IFDIR | 0o700)
            #expect(mode(of: path) == S_IFSOCK | 0o600)
        }
    }

    @Test func tightensAnExistingDirectory() throws {
        try withSocketPath { path in
            let folder = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o755])
            let server = SocketServer(path: path, handle: Self.released)
            try server.start()
            defer { server.stop() }

            #expect(mode(of: folder) == S_IFDIR | 0o700)
        }
    }

    @Test func roundTripsARequest() async throws {
        try await withSocketPath { path in
            let server = SocketServer(path: path, handle: Self.released)
            try server.start()
            defer { server.stop() }

            let reply = try await RawClient.exchange(path, releaseLine(id: "r42"))

            let response = try WireCoding.decodeResponse(try #require(reply.line), op: .release)
            #expect(response == .success(id: "r42", .release(ReleaseResult(released: true))))
        }
    }

    @Test func passesThePeerPid() async throws {
        try await withSocketPath { path in
            let seen = OSAllocatedUnfairLock<Caller?>(initialState: nil)
            let server = SocketServer(path: path) { request, caller in
                seen.withLock { $0 = caller }
                return await Self.released(request, caller)
            }
            try server.start()
            defer { server.stop() }

            _ = try await RawClient.exchange(path, releaseLine())

            let caller = try #require(seen.withLock { $0 })
            #expect(caller.pid == getpid())
            #expect(caller.uid == getuid())
        }
    }

    @Test func staleSocketIsReplaced() async throws {
        try await withSocketPath { path in
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            let stale = try RawClient.bindWithoutListening(path)
            Darwin.close(stale)
            #expect(mode(of: path).map { $0 & S_IFMT } == S_IFSOCK)

            let server = SocketServer(path: path, handle: Self.released)
            try server.start()
            defer { server.stop() }

            #expect(try await RawClient.exchange(path, releaseLine()).line != nil)
        }
    }

    @Test func refusesWhenAnotherServerIsListening() async throws {
        try await withSocketPath { path in
            let first = SocketServer(path: path, handle: Self.released)
            try first.start()
            defer { first.stop() }
            let second = SocketServer(path: path, handle: Self.released)

            #expect(throws: SocketServerError.alreadyRunning) { try second.start() }
            second.stop()

            #expect(try await RawClient.exchange(path, releaseLine()).line != nil)
        }
    }

    @Test func refusesANonSocketPath() throws {
        try withSocketPath { path in
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: URL(fileURLWithPath: path))
            let server = SocketServer(path: path, handle: Self.released)

            #expect(throws: SocketServerError.unsafePath(path)) { try server.start() }
            server.stop()

            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data("keep".utf8))
        }
    }

    @Test func refusesASymlink() throws {
        try withSocketPath { path in
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: path + ".elsewhere")
            let server = SocketServer(path: path, handle: Self.released)

            #expect(throws: SocketServerError.unsafePath(path)) { try server.start() }

            #expect(mode(of: path).map { $0 & S_IFMT } == S_IFLNK)
        }
    }

    @Test func refusesAPathTooLongForTheSocketAddress() {
        let path = "/tmp/" + String(repeating: "m", count: 120)
        let server = SocketServer(path: path, handle: Self.released)
        #expect(throws: SocketServerError.pathTooLong(path)) { try server.start() }
    }

    @Test func rejectedUidGetsNoReply() async throws {
        try await withSocketPath { path in
            let called = OSAllocatedUnfairLock(initialState: false)
            let server = SocketServer(path: path, isAllowed: { _ in false }, handle: { request, caller in
                called.withLock { $0 = true }
                return await Self.released(request, caller)
            })
            try server.start()
            defer { server.stop() }

            #expect(try await RawClient.exchange(path, releaseLine()) == .eof)
            #expect(!called.withLock { $0 })
        }
    }

    @Test func oversizedLineIsBadRequest() async throws {
        try await withSocketPath { path in
            let server = SocketServer(path: path, handle: Self.released)
            try server.start()
            defer { server.stop() }

            let huge = Data(repeating: UInt8(ascii: "a"), count: WireCoding.maxLineBytes + 1)
            let reply = try await RawClient.exchange(path, huge)

            let response = try WireCoding.decodeResponse(try #require(reply.line), op: .release)
            #expect(response == .failure(id: "", .badRequest, "Request too long"))
        }
    }

    @Test func malformedLineIsBadRequest() async throws {
        try await withSocketPath { path in
            let server = SocketServer(path: path, handle: Self.released)
            try server.start()
            defer { server.stop() }

            let reply = try await RawClient.exchange(path, Data("not json\n".utf8))

            let response = try WireCoding.decodeResponse(try #require(reply.line), op: .release)
            #expect(response == .failure(id: "", .badRequest, "Malformed request"))
        }
    }

    @Test func silentClientDoesNotBlockOthers() async throws {
        try await withSocketPath { path in
            let server = SocketServer(path: path, readTimeout: 1.5, handle: Self.released)
            try server.start()
            defer { server.stop() }

            let silent = try RawClient.connect(path)
            defer { Darwin.close(silent) }
            let start = Date()

            let reply = try await RawClient.exchange(path, releaseLine())
            #expect(reply.line != nil)
            #expect(Date().timeIntervalSince(start) < 1)
            // Answered while the silent client is still waiting on its read timeout.
            #expect(RawClient.receive(silent, timeout: 0) == .timedOut)

            let silentReply = try await RawClient.offPool { RawClient.receive(silent, timeout: 5) }
            #expect(silentReply == .eof)
            #expect(Date().timeIntervalSince(start) >= 1.4)
        }
    }

    @Test func connectionsPastTheLimitCloseAtOnce() async throws {
        try await withSocketPath { path in
            let server = SocketServer(path: path, readTimeout: 3, maxConnections: 1, handle: Self.released)
            try server.start()
            defer { server.stop() }

            let silent = try RawClient.connect(path)
            defer { Darwin.close(silent) }
            let start = Date()

            #expect(try await RawClient.exchange(path, releaseLine()) == .eof)
            #expect(Date().timeIntervalSince(start) < 1)
        }
    }

    @Test func stopRemovesTheSocket() throws {
        try withSocketPath { path in
            let server = SocketServer(path: path, handle: Self.released)
            try server.start()

            server.stop()
            server.stop()

            #expect(mode(of: path) == nil)
            #expect(throws: (any Error).self) { try RawClient.connect(path) }
        }
    }

    @Test func defaultPathIsTheSharedSocketPath() {
        #expect(SocketServer.defaultPath == WireProtocol.defaultSocketPath)
        #expect(SocketServer.defaultPath.hasSuffix("/Library/Application Support/Mooring/mooring.sock"))
    }
}

// MARK: - Helpers

func releaseLine(id: String = "r1") throws -> Data {
    try WireCoding.encodeLine(Request(
        v: WireProtocol.version, id: id, op: .release, args: .release(ReleaseArgs(kind: .off, id: nil, after: nil))
    ))
}

/// The `st_mode` at `path` without following a symlink, or nil when nothing is there.
private func mode(of path: String) -> mode_t? {
    var info = stat()
    return lstat(path, &info) == 0 ? info.st_mode : nil
}

/// Runs `body` with `/tmp/m-<8 hex>/s.sock` (not yet created) and removes the folder afterwards.
/// `/tmp` keeps the path well inside `sockaddr_un`'s 104 bytes, unlike the per-user temporary directory.
func withSocketPath<T>(_ body: (String) async throws -> T) async rethrows -> T {
    let folder = String(format: "/tmp/m-%08x", UInt32.random(in: 0...UInt32.max))
    defer { try? FileManager.default.removeItem(atPath: folder) }
    return try await body(folder + "/s.sock")
}

private func withSocketPath<T>(_ body: (String) throws -> T) rethrows -> T {
    let folder = String(format: "/tmp/m-%08x", UInt32.random(in: 0...UInt32.max))
    defer { try? FileManager.default.removeItem(atPath: folder) }
    return try body(folder + "/s.sock")
}

private struct POSIXFailure: Error {
    let call: String
    let code: Int32
}

/// A bare client over POSIX calls, independent of the server's own code.
enum RawClient {
    enum Reply: Equatable {
        case line(Data)
        case eof
        case timedOut

        var line: Data? {
            if case .line(let data) = self { return data }
            return nil
        }
    }

    static func connect(_ path: String) throws -> Int32 {
        let descriptor = try socketDescriptor()
        let result = withAddress(path) { Darwin.connect(descriptor, $0, $1) }
        guard result == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw POSIXFailure(call: "connect", code: code)
        }
        return descriptor
    }

    /// A socket file at `path` with nothing listening, as a crashed app leaves behind.
    static func bindWithoutListening(_ path: String) throws -> Int32 {
        let descriptor = try socketDescriptor()
        guard withAddress(path, { bind(descriptor, $0, $1) }) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw POSIXFailure(call: "bind", code: code)
        }
        return descriptor
    }

    static func send(_ descriptor: Int32, _ bytes: Data) {
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw in
                write(descriptor, raw.baseAddress! + offset, raw.count - offset)
            }
            guard written > 0 else { return }
            offset += written
        }
    }

    /// Reads until a newline or EOF, giving up when nothing arrives for `timeout` seconds.
    static func receive(_ descriptor: Int32, timeout: TimeInterval) -> Reply {
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, Int32(timeout * 1000)) > 0 else { return .timedOut }
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { return received.isEmpty ? .eof : .line(received) }
            received.append(contentsOf: buffer[..<count])
            if received.contains(UInt8(ascii: "\n")) { return .line(received) }
        }
    }

    /// Connects, sends `bytes`, reads one reply and closes, off the cooperative thread pool.
    static func exchange(_ path: String, _ bytes: Data, timeout: TimeInterval = 3) async throws -> Reply {
        try await offPool {
            let descriptor = try connect(path)
            defer { Darwin.close(descriptor) }
            send(descriptor, bytes)
            return receive(descriptor, timeout: timeout)
        }
    }

    static func offPool<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(with: Result { try work() }) }
        }
    }

    private static func socketDescriptor() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXFailure(call: "socket", code: errno) }
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        return descriptor
    }

    private static func withAddress(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32) -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: path.utf8.prefix(raw.count - 1))
        }
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}

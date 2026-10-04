import Darwin
import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

/// A fresh `/tmp/mc-<8 hex>` folder, short enough for `sockaddr_un`.
func makeTempFolder() throws -> String {
    let folder = "/tmp/mc-" + String(format: "%08x", UInt32.random(in: .min ... .max))
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
    return folder
}

/// Fills a `sockaddr_un` for `path` and passes it to `body` as a plain `sockaddr`.
private func withAddress(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32) -> Int32 {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
    return withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}

/// A tiny Unix socket server: reads one line per connection, then answers with `reply` or stays silent until stopped.
final class LineServer: @unchecked Sendable {
    // The lock guards `received` and `stopped`, shared by the accept thread and the test.
    private let lock = NSLock()
    private var received: [String] = []
    private var stopped = false
    let path: String
    private let reply: Data?

    init(path: String, reply: Data?) {
        self.path = path
        self.reply = reply
    }

    var requests: [String] { lock.withLock { received } }
    private var isStopped: Bool { lock.withLock { stopped } }

    func start() throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0, withAddress(path, { bind(descriptor, $0, $1) }) == 0, listen(descriptor, 8) == 0 else {
            throw POSIXError(.EADDRINUSE)
        }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        Thread { [self] in serve(descriptor) }.start()
    }

    func stop() {
        lock.withLock { stopped = true }
        unlink(path)
    }

    private func serve(_ descriptor: Int32) {
        defer { close(descriptor) }
        while !isStopped {
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 50) > 0 else { continue }
            let connection = accept(descriptor, nil, nil)
            guard connection >= 0 else { continue }
            handle(connection)
        }
    }

    private func handle(_ connection: Int32) {
        defer { close(connection) }
        _ = fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) & ~O_NONBLOCK)
        var enabled: Int32 = 1
        setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        var line = Data()
        var byte: UInt8 = 0
        while read(connection, &byte, 1) == 1, byte != UInt8(ascii: "\n") { line.append(byte) }
        lock.withLock { received.append(String(bytes: line, encoding: .utf8) ?? "") }
        guard let reply else {
            while !isStopped { usleep(20_000) }
            return
        }
        _ = reply.withUnsafeBytes { write(connection, $0.baseAddress, $0.count) }
    }
}

/// Counts launcher calls.
final class LaunchCounter: @unchecked Sendable {
    // The lock guards `count`, bumped by the client's launcher call and read by the test.
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}

private let releaseRequest = Request(v: 1, id: "t", op: .release, args: .release(ReleaseArgs(kind: .off, id: nil, after: nil)))
private let releaseReply = Response.success(id: "t", .release(ReleaseResult(released: true)))

@Test func sendsAndReceivesOneLine() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let server = LineServer(path: folder + "/s.sock", reply: try WireCoding.encodeLine(releaseReply))
    try server.start()
    defer { server.stop() }

    let client = SocketClient(path: server.path, launcher: {})
    #expect(try await client.send(releaseRequest, launch: false) == releaseReply)
    let sent = try WireCoding.encodeLine(releaseRequest)
    #expect(server.requests == [String(bytes: sent.dropLast(), encoding: .utf8)])
}

@Test func defaultPathIsTheServers() {
    #expect(SocketClient.defaultPath == WireProtocol.defaultSocketPath)
}

@Test func missingSocketWithoutLaunchIsUnreachable() async throws {
    let counter = LaunchCounter()
    let client = SocketClient(path: "/tmp/mc-missing-\(UUID().uuidString.prefix(8))/s.sock", launcher: { counter.bump() })
    await #expect(throws: CLIError.unreachable) { try await client.send(releaseRequest, launch: false) }
    #expect(counter.calls == 0)
}

@Test func refusedConnectionCountsAsUnreachable() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let path = folder + "/s.sock"
    // A socket file nobody listens on, as a crashed app leaves behind.
    let stale = socket(AF_UNIX, SOCK_STREAM, 0)
    #expect(withAddress(path, { bind(stale, $0, $1) }) == 0)
    close(stale)

    let counter = LaunchCounter()
    let client = SocketClient(path: path, launcher: { counter.bump() })
    await #expect(throws: CLIError.unreachable) { try await client.send(releaseRequest, launch: false) }
    #expect(counter.calls == 0)
}

@Test func launchIsCalledOnceThenRetried() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let server = LineServer(path: folder + "/s.sock", reply: try WireCoding.encodeLine(releaseReply))
    defer { server.stop() }

    let counter = LaunchCounter()
    let client = SocketClient(path: server.path, launchWait: 3, launcher: {
        counter.bump()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { try? server.start() }
    })
    #expect(try await client.send(releaseRequest, launch: true) == releaseReply)
    #expect(counter.calls == 1)
}

@Test func launchTimeoutWithoutAppSaysUnreachable() async throws {
    let counter = LaunchCounter()
    let client = SocketClient(
        path: "/tmp/mc-missing-\(UUID().uuidString.prefix(8))/s.sock", launchWait: 0.5, launcher: { counter.bump() },
        isAppRunning: { false }
    )
    let started = ContinuousClock.now
    await #expect(throws: CLIError.unreachable) { try await client.send(releaseRequest, launch: true) }
    #expect(ContinuousClock.now - started < .milliseconds(1500))
    #expect(counter.calls == 1)
}

@Test func launchTimeoutWithAppRunningSaysBusy() async throws {
    // The app is up but never took the connection in time: busy, not missing, and the request was never sent.
    let client = SocketClient(
        path: "/tmp/mc-missing-\(UUID().uuidString.prefix(8))/s.sock", launchWait: 0.3, launcher: {}, isAppRunning: { true }
    )
    await #expect(throws: CLIError.busy) { try await client.send(releaseRequest, launch: true) }
}

@Test func eagainMeansBusy() {
    // A full queue of waiting connections: the app is there, but the request wasn't sent.
    #expect(SocketExchange.connectError(for: EAGAIN) == .busy)
    // Nothing listening yet: nil, so the client may launch the app and retry.
    for code in [ENOENT, ECONNREFUSED, ENOTSOCK] { #expect(SocketExchange.connectError(for: code) == nil) }
    #expect(SocketExchange.connectError(for: EACCES) == .blocked)
    #expect(SocketExchange.connectError(for: EPERM) == .blocked)
    #expect(SocketExchange.connectError(for: EIO) == .unreachable)
}

@Test func silentServerIsNoAnswer() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let server = LineServer(path: folder + "/s.sock", reply: nil)
    try server.start()
    defer { server.stop() }

    let counter = LaunchCounter()
    let client = SocketClient(path: server.path, replyTimeout: 0.5, launcher: { counter.bump() })
    let started = ContinuousClock.now
    await #expect(throws: CLIError.noAnswer) { try await client.send(releaseRequest, launch: true) }
    #expect(ContinuousClock.now - started < .milliseconds(1500))
    #expect(counter.calls == 0)
}

@Test func garbledReplyIsNoAnswer() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let server = LineServer(path: folder + "/s.sock", reply: Data("not json\n".utf8))
    try server.start()
    defer { server.stop() }

    let client = SocketClient(path: server.path, launcher: {})
    await #expect(throws: CLIError.noAnswer) { try await client.send(releaseRequest, launch: false) }
}

@Test func overlongReplyIsNoAnswer() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let server = LineServer(path: folder + "/s.sock", reply: Data(repeating: UInt8(ascii: "a"), count: WireCoding.maxLineBytes + 10))
    try server.start()
    defer { server.stop() }

    let client = SocketClient(path: server.path, launcher: {})
    await #expect(throws: CLIError.noAnswer) { try await client.send(releaseRequest, launch: false) }
}

@Test func endOfFileWithoutALineIsNoAnswer() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let server = LineServer(path: folder + "/s.sock", reply: Data())
    try server.start()
    defer { server.stop() }

    let client = SocketClient(path: server.path, launcher: {})
    await #expect(throws: CLIError.noAnswer) { try await client.send(releaseRequest, launch: false) }
}

@Test func permissionDeniedIsBlocked() async throws {
    // Root ignores directory modes, so connect would never get EACCES.
    guard getuid() != 0 else { return }
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let server = LineServer(path: folder + "/s.sock", reply: try WireCoding.encodeLine(releaseReply))
    try server.start()
    defer { server.stop() }
    #expect(chmod(folder, 0o000) == 0)
    defer { chmod(folder, 0o700) }

    let counter = LaunchCounter()
    let client = SocketClient(path: server.path, launchWait: 0.5, launcher: { counter.bump() })
    await #expect(throws: CLIError.blocked) { try await client.send(releaseRequest, launch: true) }
    #expect(counter.calls == 0)
}

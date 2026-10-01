import Darwin
import Foundation
import MooringIPC

/// Talks to the app over its Unix socket: one request line out, one reply line back, per connection.
/// When nobody is listening it can start the app and retry until it answers.
public struct SocketClient: RequestSending, Sendable {
    /// Where the app listens.
    public static var defaultPath: String { WireProtocol.defaultSocketPath }

    private let path: String
    private let replyTimeout: TimeInterval
    private let launchWait: TimeInterval
    private let launcher: @Sendable () -> Void

    public init(
        path: String, replyTimeout: TimeInterval = 5, launchWait: TimeInterval = 3,
        launcher: @escaping @Sendable () -> Void = SocketClient.openApp
    ) {
        self.path = path
        self.replyTimeout = replyTimeout
        self.launchWait = launchWait
        self.launcher = launcher
    }

    /// Starts Mooring in the background without bringing it forward. The retry loop checks it came up.
    public static func openApp() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-gj", "-b", "dev.mooring.app"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    public func send(_ request: Request, launch: Bool) async throws -> Response {
        guard let line = try? WireCoding.encodeLine(request) else { throw CLIError.unreachable }
        if let response = try await attempt(line, op: request.op) { return response }
        guard launch else { throw CLIError.unreachable }

        let launcher = launcher
        try await onGlobalQueue { launcher() }
        let deadline = Date().addingTimeInterval(launchWait)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
            if let response = try await attempt(line, op: request.op) { return response }
        }
        throw CLIError.unreachable
    }

    /// One exchange on a fresh socket: the reply, or nil when nothing listens at `path` yet.
    private func attempt(_ line: Data, op: Op) async throws -> Response? { // swiftlint:disable:this identifier_name
        let path = path
        let timeout = replyTimeout
        let reply = try await onGlobalQueue { try SocketExchange.exchange(line, at: path, timeout: timeout) }
        guard let reply else { return nil }
        guard let response = try? WireCoding.decodeResponse(reply, op: op) else { throw CLIError.unreachable }
        return response
    }

    /// Runs blocking socket and process work on a global queue so it doesn't hold a Swift concurrency thread.
    private func onGlobalQueue<Value: Sendable>(_ body: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(with: Result { try body() }) }
        }
    }
}

/// The blocking POSIX calls behind `SocketClient`.
private enum SocketExchange {
    /// Sends `line` and reads one reply line, or returns nil when no server is listening at `path`.
    /// Every other failure, including a timeout, a reply over `WireCoding.maxLineBytes` and EOF before a newline, is `unreachable`.
    static func exchange(_ line: Data, at path: String, timeout: TimeInterval) throws -> Data? {
        guard var address = address(for: path) else { throw CLIError.unreachable }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CLIError.unreachable }
        defer { close(descriptor) }
        configure(descriptor, timeout: timeout)

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            switch errno {
            case ENOENT, ECONNREFUSED, ENOTSOCK: return nil
            default: throw CLIError.unreachable
            }
        }
        try writeAll(line, to: descriptor)
        return try readLine(from: descriptor)
    }

    private static func configure(_ descriptor: Int32, timeout: TimeInterval) {
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        let whole = max(0, timeout.rounded(.down))
        var interval = timeval(tv_sec: Int(whole), tv_usec: Int32((timeout - whole) * 1_000_000))
        if interval.tv_sec == 0 && interval.tv_usec == 0 { interval.tv_usec = 1 }
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw CLIError.unreachable
                }
                offset += written
            }
        }
    }

    private static func readLine(from descriptor: Int32) throws -> Data {
        var line = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(descriptor, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw CLIError.unreachable
            }
            guard count > 0 else { throw CLIError.unreachable }
            if let newline = chunk[..<count].firstIndex(of: UInt8(ascii: "\n")) {
                line.append(contentsOf: chunk[..<newline])
                guard line.count <= WireCoding.maxLineBytes else { throw CLIError.unreachable }
                return line
            }
            line.append(contentsOf: chunk[..<count])
            guard line.count <= WireCoding.maxLineBytes else { throw CLIError.unreachable }
        }
    }

    private static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        return address
    }
}

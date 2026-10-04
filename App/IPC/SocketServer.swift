import Darwin
import Foundation
import MooringIPC
import os

enum SocketServerError: LocalizedError, Equatable {
    case pathTooLong(String)
    /// Something other than a socket (or a symlink) is at the path; it is left alone.
    case unsafePath(String)
    case alreadyRunning
    case system(call: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .pathTooLong(let path): "Socket path is too long: \(path)"
        case .unsafePath(let path): "Not replacing \(path): it isn't a socket"
        case .alreadyRunning: "Another Mooring is running"
        case .system(let call, let code): "\(call) failed: \(String(cString: strerror(code)))"
        }
    }
}

/// The app's end of the CLI socket (docs/SPEC.md 2.1): one newline-delimited JSON request per
/// connection, answered by `handle`, from callers whose uid `isAllowed` accepts.
///
/// `@unchecked Sendable`: every mutable property is read and written only on `queue`, a private
/// serial queue that also runs every dispatch source and timer handler.
final class SocketServer: @unchecked Sendable {
    static var defaultPath: String { WireProtocol.defaultSocketPath }

    /// `accept(2)` on a listening descriptor: the new descriptor, or -1 and the `errno`.
    typealias Accept = @Sendable (Int32) -> (descriptor: Int32, error: Int32)

    static let liveAccept: Accept = { listening in
        let descriptor = Darwin.accept(listening, nil, nil)
        return (descriptor, descriptor < 0 ? errno : 0)
    }

    private let path: String
    private let readTimeout: TimeInterval
    private let maxConnections: Int
    private let isAllowed: @Sendable (uid_t) -> Bool
    private let accept: Accept
    private let handle: @Sendable (Request, Caller) async -> Response
    private let queue = DispatchQueue(label: "dev.mooring.ipc.socket")
    private let log = Logger(subsystem: "dev.mooring", category: "ipc")

    private var listener: DispatchSourceRead?
    /// Resumes `listener`, suspended while out of descriptors; set only while it's suspended.
    private var acceptRetry: DispatchWorkItem?
    /// Whether accepting is out of descriptors and has been logged, until a connection is accepted again.
    private var outOfDescriptors = false
    private var episodes = 0
    private var connections: [UInt64: Connection] = [:]
    private var nextID: UInt64 = 0

    /// One accepted client. Its read source lives as long as the connection; its cancel handler closes `descriptor`.
    private final class Connection {
        let descriptor: Int32
        let caller: Caller
        let source: DispatchSourceRead
        var buffer = Data()
        var isReading = true
        var timeout: DispatchWorkItem?
        var unsent = Data()
        var writeDeadline = DispatchTime.distantFuture

        init(descriptor: Int32, caller: Caller, source: DispatchSourceRead) {
            self.descriptor = descriptor
            self.caller = caller
            self.source = source
        }
    }

    init(
        path: String, readTimeout: TimeInterval = 5, maxConnections: Int = 16,
        isAllowed: @escaping @Sendable (uid_t) -> Bool = { $0 == getuid() },
        accept: @escaping Accept = SocketServer.liveAccept,
        handle: @escaping @Sendable (Request, Caller) async -> Response
    ) {
        self.path = path
        self.readTimeout = readTimeout
        self.maxConnections = maxConnections
        self.isAllowed = isAllowed
        self.accept = accept
        self.handle = handle
    }

    /// Takes over `path` and starts accepting. Throws, touching nothing, when the path is unsafe or
    /// another server answers there; a dead socket left by a crash is replaced.
    func start() throws {
        try queue.sync {
            guard listener == nil else { return }
            let descriptor = try SocketFile.listen(at: path)
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptPending(on: descriptor) }
            source.setCancelHandler { Darwin.close(descriptor) }
            source.resume()
            listener = source
            log.notice("listening on \(self.path, privacy: .private)")
        }
    }

    /// Stops accepting, drops every open connection and removes the socket file. Safe to call twice.
    func stop() {
        queue.sync {
            guard let listener else { return }
            listener.cancel()
            // A suspended source never runs its cancel handler, and freeing one crashes.
            if let acceptRetry {
                acceptRetry.cancel()
                self.acceptRetry = nil
                listener.resume()
            }
            self.listener = nil
            for id in Array(connections.keys) { drop(id) }
            unlink(path)
            log.notice("stopped listening")
        }
    }

    // MARK: - Accepting

    /// How many times accepting has run out of descriptors, each logged once however long it lasts; for tests.
    var backOffEpisodes: Int { queue.sync { episodes } }

    private func acceptPending(on listening: Int32) {
        while true {
            let (descriptor, error) = accept(listening)
            guard descriptor >= 0 else {
                if error == EMFILE || error == ENFILE { pauseAccepting() }
                return
            }
            outOfDescriptors = false
            admit(descriptor)
        }
    }

    /// Out of descriptors, the connection stays queued and the listener would fire again at once: it waits 100 ms
    /// instead, then tries again. Logged once until a connection is accepted.
    private func pauseAccepting() {
        guard let listener, acceptRetry == nil else { return }
        if !outOfDescriptors {
            outOfDescriptors = true
            episodes += 1
            log.error("out of file descriptors; retrying accept every 100 ms")
        }
        listener.suspend()
        // Resumes exactly once: here, or in `stop()`, which cancels this first.
        let retry = DispatchWorkItem { [weak self] in
            self?.acceptRetry = nil
            listener.resume()
        }
        acceptRetry = retry
        queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: retry)
    }

    private func admit(_ descriptor: Int32) {
        guard connections.count < maxConnections else {
            log.notice("too many connections; closing a new one")
            Darwin.close(descriptor)
            return
        }
        SocketFile.prepare(descriptor)
        guard let caller = SocketFile.peer(of: descriptor) else {
            Darwin.close(descriptor)
            return
        }
        guard isAllowed(caller.uid) else {
            log.notice("rejected peer uid \(caller.uid) pid \(caller.pid)")
            Darwin.close(descriptor)
            return
        }
        nextID += 1
        let id = nextID
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable(id) }
        source.setCancelHandler { Darwin.close(descriptor) }
        let connection = Connection(descriptor: descriptor, caller: caller, source: source)
        connections[id] = connection
        connection.timeout = schedule(after: readTimeout) { [weak self] in self?.drop(id) }
        source.resume()
    }

    // MARK: - Reading

    private func readAvailable(_ id: UInt64) {
        guard let connection = connections[id], connection.isReading else { return }
        let room = min(4096, WireCoding.maxLineBytes + 1 - connection.buffer.count)
        var chunk = [UInt8](repeating: 0, count: room)
        let count = read(connection.descriptor, &chunk, room)
        if count < 0 {
            if errno != EAGAIN && errno != EINTR { drop(id) }
            return
        }
        if count == 0 {
            // EOF: what arrived is the whole request, unless nothing did.
            if connection.buffer.isEmpty {
                drop(id)
            } else {
                finishReading(id, line: connection.buffer)
            }
            return
        }
        let searchFrom = connection.buffer.endIndex
        connection.buffer.append(contentsOf: chunk[..<count])
        if let newline = connection.buffer[searchFrom...].firstIndex(of: UInt8(ascii: "\n")) {
            finishReading(id, line: connection.buffer[...newline])
        } else if connection.buffer.count > WireCoding.maxLineBytes {
            finishReading(id, line: connection.buffer) // decoding rejects it as too long
        }
    }

    /// Stops reading `id` and answers `line`, straight away when it doesn't decode.
    private func finishReading(_ id: UInt64, line: Data) {
        guard let connection = connections[id] else { return }
        connection.isReading = false
        connection.source.suspend()
        connection.timeout?.cancel()
        connection.timeout = nil
        switch WireCoding.decodeRequest(Data(line)) {
        case .failure(let error):
            respond(id, .failure(id: "", error.code, error.message))
        case .success(let request):
            let handle = handle
            let caller = connection.caller
            Task {
                let response = await handle(request, caller)
                self.queue.async { self.respond(id, response) }
            }
        }
    }

    // MARK: - Writing

    private func respond(_ id: UInt64, _ response: Response) {
        guard let connection = connections[id] else { return }
        guard let line = try? WireCoding.encodeLine(response) else {
            log.error("couldn't encode a response")
            drop(id)
            return
        }
        connection.unsent = line
        connection.writeDeadline = .now() + readTimeout
        flush(id)
    }

    /// Writes what's left of the response, retrying shortly while the client's buffer is full, then closes.
    private func flush(_ id: UInt64) {
        guard let connection = connections[id] else { return }
        while !connection.unsent.isEmpty {
            let written = connection.unsent.withUnsafeBytes { write(connection.descriptor, $0.baseAddress, $0.count) }
            if written > 0 {
                connection.unsent = connection.unsent.dropFirst(written)
            } else if written < 0 && errno == EINTR {
                continue
            } else if written < 0 && errno == EAGAIN && DispatchTime.now() < connection.writeDeadline {
                queue.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in self?.flush(id) }
                return
            } else {
                break
            }
        }
        drop(id)
    }

    // MARK: - Closing

    /// Forgets `id`; cancelling its source closes the descriptor once dispatch has let go of it.
    private func drop(_ id: UInt64) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.timeout?.cancel()
        connection.source.cancel()
        // A suspended source never runs its cancel handler.
        if !connection.isReading { connection.source.resume() }
    }

    private func schedule(after seconds: TimeInterval, _ work: @escaping @Sendable () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: work)
        queue.asyncAfter(deadline: .now() + seconds, execute: item)
        return item
    }
}

/// The POSIX calls behind `SocketServer`.
private enum SocketFile {
    /// A non-blocking socket bound at `path` (mode 0600, in a 0700 folder) and listening.
    static func listen(at path: String) throws -> Int32 {
        var address = try address(for: path)
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard chmod(folder, 0o700) == 0 else { throw SocketServerError.system(call: "chmod", code: errno) }
        try clearStaleSocket(at: path, address: &address)

        let descriptor = try makeSocket()
        do {
            guard withSockaddr(&address, { bind(descriptor, $0, $1) }) == 0 else { throw failure("bind") }
            guard chmod(path, 0o600) == 0 else { throw failure("chmod") }
            guard Darwin.listen(descriptor, 16) == 0 else { throw failure("listen") }
            guard fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0 else { throw failure("fcntl") }
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        return descriptor
    }

    /// Non-blocking, close-on-exec and immune to SIGPIPE, so a vanished client can't kill the app.
    static func prepare(_ descriptor: Int32) {
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    }

    /// The connected process's uid and pid as the kernel reports them, or nil when it won't say.
    static func peer(of descriptor: Int32) -> Caller? {
        var credentials = xucred()
        var length = socklen_t(MemoryLayout<xucred>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERCRED, &credentials, &length) == 0,
              credentials.cr_version == XUCRED_VERSION else { return nil }
        var pid: pid_t = 0
        length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0 else { return nil }
        return Caller(uid: credentials.cr_uid, pid: pid)
    }

    /// Removes a socket nobody answers on; refuses anything else at `path`.
    private static func clearStaleSocket(at path: String, address: inout sockaddr_un) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT { return }
            throw failure("lstat")
        }
        guard info.st_mode & S_IFMT == S_IFSOCK else { throw SocketServerError.unsafePath(path) }

        let probe = try makeSocket()
        defer { Darwin.close(probe) }
        _ = fcntl(probe, F_SETFL, fcntl(probe, F_GETFL) | O_NONBLOCK)
        if withSockaddr(&address, { connect(probe, $0, $1) }) == 0 { throw SocketServerError.alreadyRunning }
        switch errno {
        case ECONNREFUSED:
            guard unlink(path) == 0 || errno == ENOENT else { throw failure("unlink") }
        case ENOENT:
            return
        case EINPROGRESS, EAGAIN:
            throw SocketServerError.alreadyRunning
        default:
            throw failure("connect")
        }
    }

    private static func address(for path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw SocketServerError.pathTooLong(path)
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        return address
    }

    private static func makeSocket() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw failure("socket") }
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        return descriptor
    }

    private static func withSockaddr(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32) -> Int32 {
        withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    private static func failure(_ call: String) -> SocketServerError {
        .system(call: call, code: errno)
    }
}

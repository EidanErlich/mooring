import Darwin
import Foundation
import MooringIPC

/// A child process `mooring anchor -- <command>` runs, sharing its terminal, working directory and environment.
///
/// `@unchecked Sendable`: `pid` is the only mutable state and is read and written only under `lock`,
/// since `forward` runs on the signal queue while `wait` blocks on another thread.
public final class AnchorRun: @unchecked Sendable {
    /// `posix_spawnp` refused to start the command; `code` is its errno value.
    public struct SpawnError: Error, Equatable, CustomStringConvertible {
        public let code: Int32
        public var description: String { String(cString: strerror(code)) }
    }

    private let command: [String]
    private let lock = NSLock()
    private var pid: pid_t = 0

    public init(command: [String]) {
        self.command = command
    }

    /// Spawns the command, looking it up on PATH, and returns its pid.
    public func start() throws -> Int32 {
        guard let program = command.first else { throw SpawnError(code: EINVAL) }
        let argv: [UnsafeMutablePointer<CChar>?] = command.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        // The child gets an empty signal mask: the calling thread is a worker thread that blocks most
        // signals, and an inherited mask would keep the child from ever seeing a forwarded INT or TERM.
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var unblocked: sigset_t = 0
        posix_spawnattr_setsigmask(&attributes, &unblocked)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGMASK))
        var child: pid_t = 0
        let result = posix_spawnp(&child, program, nil, &attributes, argv, environ)
        guard result == 0 else { throw SpawnError(code: result) }
        lock.withLock { pid = child }
        return child
    }

    /// Sends `signal` to the child, if it is still running.
    public func forward(_ signal: Int32) {
        lock.withLock {
            guard pid > 0 else { return }
            kill(pid, signal)
        }
    }

    /// Blocks until the child exits and returns its exit status, or 128 + the signal that ended it.
    public func wait() -> Int32 {
        let child = lock.withLock { pid }
        guard child > 0 else { return 1 }
        var status: Int32 = 0
        while waitpid(child, &status, 0) < 0 {
            guard errno == EINTR else { return 1 }
        }
        lock.withLock { pid = 0 }
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }
}

/// `mooring anchor -- <command>`: runs the command under an anchor lease that ends when it exits.
struct AnchoredCommand {
    let env: CLIEnvironment
    let options: OutputOptions
    let command: [String]
    let level: String?
    let reason: String?
    let agent: String?

    /// The child's exit code; 3 when the app can't be reached (the command never starts), 127 when it can't be spawned.
    func run() async -> Int32 {
        guard await appIsReachable() else { return CommandRunner(env: env, options: options).unreachable() }
        let child = AnchorRun(command: command)
        let pid: Int32
        do {
            pid = try child.start()
        } catch {
            env.writeError("mooring: \(command[0]): \(error)\n")
            return 127
        }
        let forwarding = SignalForwarding(to: child)
        defer { forwarding.stop() }
        await acquire(watching: pid)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: child.wait()) }
        }
    }

    /// False only when the app is unreachable; any other failure is left for the acquire to report.
    private func appIsReachable() async -> Bool {
        let request = Request(v: WireProtocol.version, id: env.newID(), op: .status, args: .status)
        do {
            _ = try await env.client.send(request, launch: !options.noLaunch)
            return true
        } catch CLIError.unreachable {
            return false
        } catch {
            return true
        }
    }

    /// Takes the lease, warning on stderr when it can't; the command runs either way.
    private func acquire(watching pid: Int32) async {
        let args = AcquireArgs(
            kind: .anchor, id: nil, level: (try? CLIParse.level(level)) ?? nil, ttl: nil, watchPid: pid,
            reason: reason ?? command.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines), agent: agent
        )
        let request = Request(v: WireProtocol.version, id: env.newID(), op: .acquire, args: .acquire(args))
        let problem: String
        do {
            let response = try await env.client.send(request, launch: !options.noLaunch)
            if response.ok { return }
            let error = response.error ?? WireError(code: .internal, message: "Unexpected reply from Mooring")
            if error.code == .guardrail {
                env.writeError("mooring: \(error.message)\n")
                return
            }
            problem = error.message
        } catch CLIError.unreachable {
            problem = "Mooring isn't running"
        } catch {
            problem = "Couldn't talk to Mooring"
        }
        env.writeError("mooring: couldn't anchor (\(problem)); running without it\n")
    }
}

/// Passes INT, TERM and HUP on to the child while it runs, instead of letting them end `mooring` first.
private final class SignalForwarding {
    private static let forwarded = [SIGINT, SIGTERM, SIGHUP]
    private let queue = DispatchQueue(label: "dev.mooring.cli.signals")
    private var sources: [DispatchSourceSignal] = []
    private var previous: [sig_t?] = []

    init(to child: AnchorRun) {
        for number in Self.forwarded {
            previous.append(signal(number, SIG_IGN))
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { child.forward(number) }
            source.resume()
            sources.append(source)
        }
    }

    /// Stops forwarding and puts back the handlers that were there before.
    func stop() {
        for (index, number) in Self.forwarded.enumerated() {
            sources[index].cancel()
            signal(number, previous[index])
        }
    }
}

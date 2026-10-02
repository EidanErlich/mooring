import Foundation
import MooringIPC

/// Sends one request to the running app and returns its reply.
public protocol RequestSending: Sendable {
    /// Throws `CLIError.unreachable` when the app isn't there (after trying to launch it, if `launch`),
    /// `.noAnswer` when it was reached but didn't reply, and `.blocked` when the socket may not be opened.
    func send(_ request: Request, launch: Bool) async throws -> Response
}

public enum CLIError: Error, Equatable {
    /// The command line was wrong; the message says how.
    case usage(String)
    /// Nothing listens on the socket and the app couldn't be started.
    case unreachable
    /// The app accepted the connection but didn't give a usable reply; the request may have gone through.
    case noAnswer
    /// The system refused access to the socket, as a sandbox does.
    case blocked
}

extension CLIError {
    /// What is printed (and sent as the `--json` error message) when the app can't be used; nil for `.usage`.
    /// All three are exit code 3 and the `unreachable` error code.
    var unavailableMessage: String? {
        switch self {
        case .usage: nil
        case .unreachable: "Mooring isn't running and couldn't be started"
        case .noAnswer: "Mooring didn't answer. It may be busy; the request may have gone through, so check `mooring status`."
        case .blocked:
            "Can't reach Mooring's socket (permission denied). "
                + "If this runs in a sandbox, allow ~/Library/Application Support/Mooring/mooring.sock"
        }
    }
}

/// Everything a command touches outside its own arguments, so tests can replace it.
public struct CLIEnvironment: Sendable {
    public var client: any RequestSending
    public var processes: any ProcessTable
    public var ownPID: Int32
    public var parentPID: Int32
    public var write: @Sendable (String) -> Void
    public var writeError: @Sendable (String) -> Void
    public var newID: @Sendable () -> String
    public var now: @Sendable () -> Date
    /// Where this `mooring` binary lives, for doctor's PATH check.
    public var ownBinaryPath: String
    /// The caller's `PATH`, or nil when it has none.
    public var pathEnv: String?
    /// Reads at most the given number of bytes from stdin.
    public var readInput: @Sendable (Int) -> Data
    /// What `mooring hook` sends through: a quick client that gives up fast.
    public var hookClient: any RequestSending

    public init(
        client: any RequestSending, processes: any ProcessTable, ownPID: Int32, parentPID: Int32,
        write: @escaping @Sendable (String) -> Void, writeError: @escaping @Sendable (String) -> Void,
        newID: @escaping @Sendable () -> String, now: @escaping @Sendable () -> Date,
        ownBinaryPath: String, pathEnv: String?,
        readInput: @escaping @Sendable (Int) -> Data, hookClient: any RequestSending
    ) {
        self.client = client
        self.processes = processes
        self.ownPID = ownPID
        self.parentPID = parentPID
        self.write = write
        self.writeError = writeError
        self.newID = newID
        self.now = now
        self.ownBinaryPath = ownBinaryPath
        self.pathEnv = pathEnv
        self.readInput = readInput
        self.hookClient = hookClient
    }
}

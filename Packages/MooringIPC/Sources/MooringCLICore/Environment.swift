import Foundation
import MooringIPC

/// Sends one request to the running app and returns its reply.
public protocol RequestSending: Sendable {
    /// Throws `CLIError.unreachable` when the app can't be reached (after trying to launch it, if `launch`).
    func send(_ request: Request, launch: Bool) async throws -> Response
}

public enum CLIError: Error, Equatable {
    /// The command line was wrong; the message says how.
    case usage(String)
    /// The app didn't answer and couldn't be started.
    case unreachable
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

    public init(
        client: any RequestSending, processes: any ProcessTable, ownPID: Int32, parentPID: Int32,
        write: @escaping @Sendable (String) -> Void, writeError: @escaping @Sendable (String) -> Void,
        newID: @escaping @Sendable () -> String, now: @escaping @Sendable () -> Date
    ) {
        self.client = client
        self.processes = processes
        self.ownPID = ownPID
        self.parentPID = parentPID
        self.write = write
        self.writeError = writeError
        self.newID = newID
        self.now = now
    }
}

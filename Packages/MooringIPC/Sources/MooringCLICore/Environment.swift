import Foundation
import MooringIPC

/// Sends one request to the running app and returns its reply.
public protocol RequestSending: Sendable {
    /// Throws `CLIError.unreachable` when the app isn't there (after trying to launch it, if `launch`),
    /// `.noAnswer` when it was reached but didn't reply, `.busy` when it is running but didn't take the connection, and
    /// `.blocked` when the socket may not be opened.
    func send(_ request: Request, launch: Bool) async throws -> Response
}

public enum CLIError: Error, Equatable {
    /// The command line was wrong; the message says how.
    case usage(String)
    /// Nothing listens on the socket and the app isn't running, even after trying to start it.
    case unreachable
    /// The app accepted the connection but didn't give a usable reply; the request may have gone through.
    case noAnswer
    /// The app is running but didn't take the connection in time, so the request was never sent.
    case busy
    /// The system refused access to the socket, as a sandbox does.
    case blocked
}

extension CLIError {
    /// What is printed (and sent as the `--json` error message) when the app can't be used; nil for `.usage`.
    /// All four are exit code 3 and the `unreachable` error code.
    var unavailableMessage: String? {
        switch self {
        case .usage: nil
        case .unreachable: "Mooring isn't running and couldn't be started"
        case .noAnswer: "Mooring didn't answer. It may be busy; the request may have gone through, so check `mooring status`."
        case .busy: "Mooring is running but didn't answer. Try again in a moment."
        case .blocked:
            "Can't reach Mooring's socket (permission denied). "
                + "If this runs in a sandbox, allow ~/Library/Application Support/Mooring/mooring.sock"
        }
    }
}

/// What `claude` reported to `mooring doctor`. A nil member means that part couldn't be read.
public struct ClaudeSnapshot: Sendable, Equatable {
    /// `claude --version`, e.g. "2.1.285".
    public var version: String?
    /// `claude plugin list --json`.
    public var plugins: [ClaudeCode.InstalledPlugin]?
    /// The Claude Code major.minor the installed plugin was tested with (its `mooring.json`).
    public var testedWith: String?

    public init(version: String?, plugins: [ClaudeCode.InstalledPlugin]?, testedWith: String?) {
        self.version = version
        self.plugins = plugins
        self.testedWith = testedWith
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
    /// The user's home folder, where doctor looks for MCP client configs.
    public var home: URL
    /// Reads at most the given number of bytes from stdin.
    public var readInput: @Sendable (Int) -> Data
    /// What `mooring hook` sends through: a quick client that gives up fast.
    public var hookClient: any RequestSending
    /// What an acquire whose level includes lid goes through: it waits long enough for the user to answer an approval.
    public var lidClient: any RequestSending
    /// What `mooring win list` and a mutating `mooring win` request go through: an ask (60 s), a wait in the queue and
    /// launching apps can add up to more than `lidClient`'s 65 s, and a list can wait on several hung apps.
    public var windowClient: any RequestSending
    /// Asks Claude Code about itself, for doctor. Blocks for a few seconds at most; nil when `claude` isn't found.
    public var claude: @Sendable () -> ClaudeSnapshot?
    /// Reads one line from stdin without its newline, blocking until it arrives; nil at end of input. For `mooring mcp`.
    public var readLine: @Sendable () -> String?
    /// The version of the app this binary ships in (`AppVersion.current`), which `--version` prints and `mooring mcp`
    /// reports to its client.
    public var appVersion: String

    /// The client for an acquire of `kind` at `level` (a canonical level name, or nil for the app's default): the long-wait
    /// one when it may need an approval, since the app can hold the reply for up to a minute. That is a level that includes
    /// lid, or a plain `on`, which starts at the menu bar's click level, and that can be lid.
    func acquireClient(kind: AcquireKind, level: String?) -> any RequestSending {
        guard let level else { return kind == .on ? lidClient : client }
        return WireText.parseLevel(level)?.lid == true ? lidClient : client
    }

    public init(
        client: any RequestSending, processes: any ProcessTable, ownPID: Int32, parentPID: Int32,
        write: @escaping @Sendable (String) -> Void, writeError: @escaping @Sendable (String) -> Void,
        newID: @escaping @Sendable () -> String, now: @escaping @Sendable () -> Date,
        ownBinaryPath: String, pathEnv: String?, home: URL,
        readInput: @escaping @Sendable (Int) -> Data, hookClient: any RequestSending,
        lidClient: any RequestSending, windowClient: any RequestSending, claude: @escaping @Sendable () -> ClaudeSnapshot?,
        readLine: @escaping @Sendable () -> String?, appVersion: String
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
        self.home = home
        self.readInput = readInput
        self.hookClient = hookClient
        self.lidClient = lidClient
        self.windowClient = windowClient
        self.claude = claude
        self.readLine = readLine
        self.appVersion = appVersion
    }
}

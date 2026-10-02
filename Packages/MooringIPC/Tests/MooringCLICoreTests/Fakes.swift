import Foundation
import MooringIPC
@testable import MooringCLICore

/// Records the requests it is given and answers with a canned reply.
final class RecordingClient: RequestSending, @unchecked Sendable {
    // The lock guards the recorded values, which the CLI writes from its own task and tests read after it returns.
    private let lock = NSLock()
    private var recorded: [(request: Request, launch: Bool)] = []
    private var cannedReply: Result<Response, CLIError>

    init(reply: Result<Response, CLIError> = .success(.success(id: "r", .release(ReleaseResult(released: true))))) {
        cannedReply = reply
    }

    var requests: [Request] { lock.withLock { recorded.map(\.request) } }
    var lastRequest: Request? { requests.last }
    var lastLaunch: Bool? { lock.withLock { recorded.last?.launch } }

    func reply(with response: Response) {
        lock.withLock { cannedReply = .success(response) }
    }

    func fail(with error: CLIError) {
        lock.withLock { cannedReply = .failure(error) }
    }

    func send(_ request: Request, launch: Bool) async throws -> Response {
        let reply = lock.withLock {
            recorded.append((request, launch))
            return cannedReply
        }
        return try reply.get()
    }
}

func proc(_ pid: Int32, _ parent: Int32, _ name: String) -> ProcessEntry {
    ProcessEntry(pid: pid, parent: parent, name: name)
}

/// A process table from a list of entries.
struct FakeProcessTable: ProcessTable {
    let entries: [Int32: ProcessEntry]

    init(_ rows: [ProcessEntry]) {
        entries = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
    }

    func entry(_ pid: Int32) -> ProcessEntry? { entries[pid] }
}

/// Collects what the CLI writes.
final class Capture: @unchecked Sendable {
    // The lock guards the text, which the CLI appends to from its own task.
    private let lock = NSLock()
    private var out = ""
    private var err = ""

    var stdout: String { lock.withLock { out } }
    var stderr: String { lock.withLock { err } }

    func writeOut(_ text: String) { lock.withLock { out += text } }
    func writeErr(_ text: String) { lock.withLock { err += text } }
}

let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

/// A CLI wired to fakes: run arguments through it, then inspect the client and the captured output.
struct Harness {
    let client: RecordingClient
    /// What `mooring hook` sends through, kept apart from `client` so a test can tell them apart.
    let hookClient: RecordingClient
    /// What an acquire at a lid level goes through, kept apart from `client` so a test can tell them apart.
    let lidClient: RecordingClient
    let capture = Capture()
    let table: FakeProcessTable
    let parentPID: Int32
    let ownBinaryPath: String
    let pathEnv: String?
    /// What stdin holds for `mooring hook`.
    let input: Data
    /// What `claude` reported to doctor; nil when it wasn't found.
    let claude: ClaudeSnapshot?

    init(
        client: RecordingClient = RecordingClient(), hookClient: RecordingClient = RecordingClient(),
        lidClient: RecordingClient = RecordingClient(),
        table: FakeProcessTable = FakeProcessTable([]), parentPID: Int32 = 100,
        ownBinaryPath: String = "/nowhere/mooring", pathEnv: String? = nil, input: Data = Data(),
        claude: ClaudeSnapshot? = nil
    ) {
        self.client = client
        self.hookClient = hookClient
        self.lidClient = lidClient
        self.input = input
        self.claude = claude
        self.table = table
        self.parentPID = parentPID
        self.ownBinaryPath = ownBinaryPath
        self.pathEnv = pathEnv
    }

    func run(_ arguments: [String]) async -> Int32 {
        let capture = capture
        let input = input
        let claude = claude
        let environment = CLIEnvironment(
            client: client, processes: table, ownPID: 500, parentPID: parentPID,
            write: { capture.writeOut($0) }, writeError: { capture.writeErr($0) },
            newID: { "req-1" }, now: { fixedNow }, ownBinaryPath: ownBinaryPath, pathEnv: pathEnv,
            readInput: { Data(input.prefix($0)) }, hookClient: hookClient, lidClient: lidClient, claude: { claude }
        )
        return await MooringCLI.run(arguments, environment: environment)
    }
}

func leaseInfo(
    id: String = "job", owner: OwnerInfo = OwnerInfo(kind: "agent", name: "Claude Code"), reason: String = "tests",
    level: String = "system", expiresAt: Date? = nil, watchPid: Int32? = nil, ttl: Double? = nil,
    pendingApproval: Bool = false
) -> LeaseInfo {
    LeaseInfo(id: id, owner: owner, reason: reason, level: level, expiresAt: expiresAt, watchPid: watchPid, ttl: ttl,
              pendingApproval: pendingApproval)
}

func acquired(_ lease: LeaseInfo, clamped: Bool = false) -> Response {
    .success(id: "r", .acquire(AcquireResult(lease: lease, clamped: clamped)))
}

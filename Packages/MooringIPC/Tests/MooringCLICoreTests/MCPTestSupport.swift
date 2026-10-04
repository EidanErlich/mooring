import Foundation
import MooringIPC
@testable import MooringCLICore

/// Records each request and answers it with what `answer` makes of it.
final class ScriptedClient: RequestSending, @unchecked Sendable {
    // The lock guards the recorded requests, which the server appends to from its own task.
    private let lock = NSLock()
    private var recorded: [Request] = []
    private let answer: @Sendable (Request) -> Result<Response, CLIError>

    init(_ answer: @escaping @Sendable (Request) -> Result<Response, CLIError> = { .success(plausibleReply(to: $0)) }) {
        self.answer = answer
    }

    var requests: [Request] { lock.withLock { recorded } }

    func send(_ request: Request, launch: Bool) async throws -> Response {
        lock.withLock { recorded.append(request) }
        return try answer(request).get()
    }
}

/// A success the app could have sent for `request`: the lease it asked for, a release, a status or a posted notification.
func plausibleReply(to request: Request) -> Response {
    switch request.args {
    case .acquire(let args):
        let lease = leaseInfo(
            id: args.id ?? "lease", owner: OwnerInfo(kind: "mcp", name: MCPClientName.display(args.client)),
            reason: args.reason ?? "", level: args.level ?? "system",
            expiresAt: args.ttl.map { fixedNow.addingTimeInterval($0) }, watchPid: args.watchPid, ttl: args.ttl
        )
        return .success(id: request.id, .acquire(AcquireResult(lease: lease, clamped: false)))
    case .release: return .success(id: request.id, .release(ReleaseResult(released: true)))
    case .notify: return .success(id: request.id, .notify(NotifyResult(posted: true)))
    case .status: return .success(id: request.id, .status(statusResult(leases: [])))
    case .renew(let args): return .success(id: request.id, .renew(leaseInfo(id: args.id)))
    case .hook: return .success(id: request.id, .hook(HookResult(action: "ignore")))
    case .winList: return .success(id: request.id, .winList(WinListResult(apps: [], screens: [], regions: [])))
    case .winArrange(let plan):
        let results = plan.placements.map { WinPlacementResult(app: $0.app, status: .ok) }
        return .success(id: request.id, .winArrange(WinArrangeResult(results: results, undoAvailable: true)))
    case .winUndo: return .success(id: request.id, .winUndo(WinArrangeResult(results: [], undoAvailable: false)))
    case .winLayout: return .success(id: request.id, .winLayout(WinLayoutResult(names: [], arrange: nil)))
    }
}

func statusResult(leases: [LeaseInfo]) -> StatusResult {
    StatusResult(
        summary: "On · lid mode · 20m left", effective: LevelInfo(system: true, display: false, lid: true),
        systemAssertion: true, displayAssertion: false, lidSleepDisabled: true, helperSleepDisabled: true, wantsLid: true,
        leases: leases, power: PowerInfo(onAC: false, batteryPercent: 64), thermal: "fair", lidClosed: false,
        helper: "enabled", suspensions: [], notifications: "allowed", agentLidApproval: "askWhenOpenEnded"
    )
}

/// Hands out scripted stdin lines, then nil for end of input.
final class LineFeed: @unchecked Sendable {
    // The lock guards the remaining lines, which the server reads from a background queue.
    private let lock = NSLock()
    private var lines: [String]

    init(_ lines: [String]) { self.lines = lines }

    func next() -> String? {
        lock.withLock { lines.isEmpty ? nil : lines.removeFirst() }
    }
}

/// An MCP server wired to fakes: feed it lines, then read its replies.
struct MCPHarness {
    static let defaultPID: Int32 = 500
    static let appVersion = "9.9.9-test"

    /// The pid of this `mooring mcp` process, which its leases watch and their ids carry.
    var ownPID = defaultPID
    var client = ScriptedClient()
    var lidClient = ScriptedClient()
    let capture = Capture()

    func run(_ lines: [String]) async -> Int32 {
        let feed = LineFeed(lines)
        let capture = capture
        let environment = CLIEnvironment(
            client: client, processes: FakeProcessTable([proc(ownPID, 90, "mooring")]), ownPID: ownPID, parentPID: 90,
            write: { capture.writeOut($0) }, writeError: { capture.writeErr($0) },
            newID: { "req-1" }, now: { fixedNow }, ownBinaryPath: "/nowhere/mooring", pathEnv: nil,
            home: URL(fileURLWithPath: "/nowhere/home"),
            readInput: { _ in Data() }, hookClient: ScriptedClient(), lidClient: lidClient, claude: { nil },
            readLine: { feed.next() }, appVersion: Self.appVersion
        )
        return await MCPServer(environment: environment).run()
    }

    /// Every stdout line, parsed as a JSON object.
    var replies: [[String: Any]] {
        capture.stdout.split(separator: "\n").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
        }
    }

    /// The tool result in the reply with JSON-RPC id `id`.
    func toolResult(_ id: Int) -> [String: Any]? {
        reply(id)?["result"] as? [String: Any]
    }

    func reply(_ id: Int) -> [String: Any]? {
        replies.first { ($0["id"] as? Int) == id }
    }

    /// The text of the tool result with id `id`.
    func text(_ id: Int) -> String? {
        ((toolResult(id)?["content"] as? [[String: Any]])?.first?["text"]) as? String
    }

    /// The tool result's `isError`, or nil when reply `id` is missing or isn't a tool result, so
    /// `isError(n) == false` holds only for a real success.
    func isError(_ id: Int) -> Bool? {
        toolResult(id)?["isError"] as? Bool
    }

    /// The tool result's `structuredContent`.
    func structured(_ id: Int) -> [String: Any]? {
        toolResult(id)?["structuredContent"] as? [String: Any]
    }

    var allRequests: [Request] { client.requests + lidClient.requests }
}

/// A JSON-RPC request line.
func rpc(_ id: Int, _ method: String, _ params: String = "{}") -> String {
    #"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)","params":\#(params)}"#
}

/// An `initialize` request from a client named `name` speaking `version`.
func initialize(_ name: String = "claude-ai", version: String = "2025-06-18", id: Int = 1) -> String {
    rpc(id, "initialize", #"{"protocolVersion":"\#(version)","capabilities":{},"clientInfo":{"name":"\#(name)","version":"1.0"}}"#)
}

/// A `tools/call` request for `tool` with `arguments` (a JSON object).
func call(_ id: Int, _ tool: String, _ arguments: String = "{}") -> String {
    rpc(id, "tools/call", #"{"name":"\#(tool)","arguments":\#(arguments)}"#)
}

func acquireArgs(of request: Request?) -> AcquireArgs? {
    if case .acquire(let args)? = request?.args { return args }
    return nil
}

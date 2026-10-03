import Foundation
import MooringIPC

/// `mooring mcp`: an MCP server on stdin and stdout that relays each tool call to the app's socket.
///
/// It reads newline-delimited JSON-RPC one line at a time and answers each request before reading the next. Bad lines get
/// a JSON-RPC error and the loop carries on; only end of input stops it.
public struct MCPServer {
    private let environment: CLIEnvironment

    public init(environment: CLIEnvironment) {
        self.environment = environment
    }

    /// Serves until stdin ends, then returns 0.
    public func run() async -> Int32 {
        var session = MCPSession(environment: environment)
        while let line = await nextLine() {
            if let reply = await session.handle(line) { environment.write(reply) }
        }
        return 0
    }

    /// The next stdin line, read on a background queue so a blocking read never holds a concurrency thread.
    private func nextLine() async -> String? {
        let read = environment.readLine
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: read()) }
        }
    }
}

/// What one server remembers between lines: who the client said it was, and the leases it created for that client.
struct MCPSession {
    static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    let environment: CLIEnvironment
    /// `clientInfo.name` from `initialize`, as the client sent it; nil until then.
    private(set) var clientName: String?
    /// How many lease ids this server has made, for the `-<n>` suffix of the next.
    private var leasesMade = 0
    /// The ids this server created, oldest first. Only these may be extended or released.
    private(set) var ownLeases: [String] = []

    init(environment: CLIEnvironment) {
        self.environment = environment
    }

    /// The client's name as the app shows it.
    var displayName: String { MCPClientName.display(clientName) }

    /// `client` for the app: the reported name, or "" before `initialize` names one, so every request is a client's.
    var wireClient: String { clientName ?? "" }

    /// The reply line to `line`, or nil when it needs none.
    mutating func handle(_ line: String) async -> String? {
        if line.utf8.count <= MCPMessage.maxLineBytes, line.allSatisfy(\.isWhitespace) { return nil }
        switch MCPMessage.parse(line) {
        case .failure(let error):
            environment.writeError("mooring mcp: \(error.message) (a line of \(line.utf8.count) bytes)\n")
            return MCPMessage.errorLine(id: .null, error)
        case .success(.reply), .success(.notification):
            return nil
        case .success(.request(let id, let method, let params)):
            switch await respond(to: method, params: params) {
            case .success(let result): return MCPMessage.resultLine(id: id, result)
            case .failure(let error): return MCPMessage.errorLine(id: id, error)
            }
        }
    }

    private mutating func respond(to method: String, params: JSONValue?) async -> Result<JSONValue, RPCError> {
        switch method {
        case "initialize":
            return .success(initialize(params))
        case "ping":
            return .success(.object([:]))
        case "tools/list":
            return .success(MCPTools.listResult)
        case "tools/call":
            guard let name = params?["name"]?.stringValue else { return .failure(.invalidParams("Missing tool name")) }
            switch MCPTools.parse(name: name, arguments: params?["arguments"]) {
            case .unknownTool: return .failure(.invalidParams("Unknown tool: \(name.prefix(64))"))
            case .invalid(let message): return .success(MCPTools.failure(message))
            case .call(let call): return .success(await perform(call))
            }
        default:
            return .failure(.methodNotFound)
        }
    }

    /// Agrees on a protocol version (the client's if supported, else the newest) and remembers the client's name.
    private mutating func initialize(_ params: JSONValue?) -> JSONValue {
        if let name = params?["clientInfo"]?["name"]?.stringValue { clientName = name }
        let asked = params?["protocolVersion"]?.stringValue
        let version = asked.flatMap { Self.supportedVersions.contains($0) ? $0 : nil } ?? Self.supportedVersions[0]
        return .object([
            "protocolVersion": .string(version),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object(["name": .string("mooring"), "version": .string(environment.appVersion)])
        ])
    }

    private mutating func perform(_ call: MCPTools.Call) async -> JSONValue {
        switch call {
        case .keepAwake(let minutes, let level, let reason, let leaseID):
            await keepAwake(minutes: minutes, level: level, reason: reason, leaseID: leaseID)
        case .release(let leaseID): await release(leaseID)
        case .status: await status()
        case .notify(let title, let body): await notify(title: title, body: body)
        }
    }
}

// MARK: - Tools

extension MCPSession {
    /// Creates `mcp-<slug>-<pid>-<n>`, or extends one of this client's leases, watching this server's own process. The pid
    /// keeps two servers for one client (two Claude Code sessions, say) from sharing, and so merging, a lease. At most
    /// 4 + 24 + 1 + 10 + 1 + n digits, well within the app's 64-character ids.
    private mutating func keepAwake(minutes: Int, level: String, reason: String?, leaseID: String?) async -> JSONValue {
        let id: String
        if let leaseID {
            guard ownLeases.contains(leaseID) else { return MCPTools.failure(MCPTools.foreignLease) }
            id = leaseID
        } else {
            leasesMade += 1
            id = "mcp-\(MCPClientName.slug(displayName))-\(environment.ownPID)-\(leasesMade)"
        }
        let ttl = Double(minutes * 60)
        let args = RequestArgs.acquire(AcquireArgs(
            kind: .lease, id: id, level: level, ttl: ttl, watchPid: environment.ownPID,
            reason: reason ?? "Requested by \(displayName)", agent: nil, client: wireClient
        ))
        switch await send(args, through: environment.acquireClient(kind: .lease, level: level)) {
        case .done(let result, let request):
            remember(id)
            return MCPTools.result(humanText(result, for: request), structured: JSONValue(encoding: result))
        case .held(let guardrail):
            // The app keeps the lease and applies it when the guardrail clears, so this is a success the client must know about.
            remember(id)
            let endsAt = ISO8601DateFormatter().string(from: environment.now().addingTimeInterval(ttl))
            return MCPTools.result("Lease \(id) (\(level), \(CLIText.remaining(ttl))): \(guardrail)", structured: .object([
                "lease_id": .string(id), "level": .string(level), "ends_at": .string(endsAt), "guardrail": .string(guardrail)
            ]))
        case .failed(let message, let lost):
            // A lost reply may have created the lease, so it may be ours to release.
            if lost { remember(id) }
            return MCPTools.failure(message)
        }
    }

    /// Releases `leaseID`, or every lease this server created when it's nil.
    private mutating func release(_ leaseID: String?) async -> JSONValue {
        if let leaseID, !ownLeases.contains(leaseID) { return MCPTools.failure(MCPTools.foreignLease) }
        let ids = leaseID.map { [$0] } ?? ownLeases
        guard !ids.isEmpty else { return MCPTools.result("No leases to release", structured: .object(["released": .array([])])) }
        var lines: [String] = []
        var released: [JSONValue] = []
        for id in ids {
            switch await send(.release(ReleaseArgs(kind: .lease, id: id, after: nil)), through: environment.client) {
            case .done(let result, let request):
                ownLeases.removeAll { $0 == id }
                lines.append(humanText(result, for: request))
                if case .release(let outcome) = result, outcome.released { released.append(.string(id)) }
            case .held(let message), .failed(let message, _):
                return MCPTools.failure((lines + [message]).joined(separator: "; "))
            }
        }
        return MCPTools.result(lines.joined(separator: "; "), structured: .object(["released": .array(released)]))
    }

    /// The app's state, with only the leases this server holds for this client.
    private func status() async -> JSONValue {
        switch await send(.status, through: environment.client) {
        case .done(.status(let status), _):
            let mine = status.leases.filter {
                $0.owner.kind == "mcp" && $0.owner.name == displayName && $0.watchPid == environment.ownPID
            }
            let summary = JSONValue.object([
                "summary": .string(status.summary),
                "effective": JSONValue(encoding: status.effective),
                "leases": .array(mine.map(Self.leaseSummary)),
                "batteryPercent": status.power.batteryPercent.map(JSONValue.int) ?? .null,
                "onAC": .bool(status.power.onAC),
                "thermal": .string(status.thermal)
            ])
            return MCPTools.result(summary.compactText, structured: summary)
        case .done:
            return MCPTools.failure(Self.unexpectedReply)
        case .held(let message), .failed(let message, _):
            return MCPTools.failure(message)
        }
    }

    private func notify(title: String, body: String?) async -> JSONValue {
        switch await send(.notify(NotifyArgs(title: title, body: body, client: wireClient)), through: environment.client) {
        case .done(.notify(let result), _):
            return MCPTools.result(result.posted ? "Notification posted" : "Notification not posted",
                                   structured: JSONValue(encoding: result))
        case .done:
            return MCPTools.failure(Self.unexpectedReply)
        case .held(let message), .failed(let message, _):
            return MCPTools.failure(message)
        }
    }

    private static func leaseSummary(_ lease: LeaseInfo) -> JSONValue {
        .object([
            "id": .string(lease.id),
            "level": .string(lease.level),
            "reason": .string(lease.reason),
            "expiresAt": lease.expiresAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
            "pendingApproval": .bool(lease.pendingApproval)
        ])
    }

    private mutating func remember(_ id: String) {
        if !ownLeases.contains(id) { ownLeases.append(id) }
    }
}

// MARK: - Talking to the app

extension MCPSession {
    fileprivate static let unexpectedReply = "Unexpected reply from Mooring"

    fileprivate enum Outcome {
        case done(ResponseResult, Request)
        /// A guardrail holds back what was asked for, but the app keeps it.
        case held(String)
        /// `lost`: the reply never came, so the request may have gone through.
        case failed(String, lost: Bool)
    }

    /// Sends one request, starting the app if it isn't running, and puts any failure into the CLI's words.
    fileprivate func send(_ args: RequestArgs, through client: any RequestSending) async -> Outcome {
        let request = Request(v: WireProtocol.version, id: environment.newID(), op: CommandRunner.op(of: args), args: args)
        do {
            let response = try await client.send(request, launch: true)
            if response.ok, let result = response.result { return .done(result, request) }
            let error = response.error ?? WireError(code: .internal, message: Self.unexpectedReply)
            return error.code == .guardrail ? .held(error.message) : .failed(error.message, lost: false)
        } catch let error as CLIError {
            let message = error.unavailableMessage ?? "Couldn't talk to Mooring"
            environment.writeError("mooring mcp: \(message)\n")
            return .failed(message, lost: error == .noAnswer)
        } catch {
            environment.writeError("mooring mcp: Couldn't talk to Mooring\n")
            return .failed("Couldn't talk to Mooring", lost: false)
        }
    }

    fileprivate func humanText(_ result: ResponseResult, for request: Request) -> String {
        CLIText.human(result, for: request.args, now: environment.now(), processes: environment.processes)
    }
}

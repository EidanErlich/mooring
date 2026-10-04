import AwakeKit
import Foundation
import MooringIPC
@testable import Mooring

/// What the handler's injected closures read, changed by tests.
@MainActor
final class RequestKnobs {
    var clock = Date(timeIntervalSince1970: 1_000_000)
    var settings = AwakeSettings()
    var helperSleepDisabled: Bool?
    var notifications: String? = "allowed"
    var windowsState = WindowsController.State.off
    /// The handler's arranger; it's only used while `windowsState` is on.
    var arranger: Arranger?
}

/// Process ancestry for agent detection; empty, so callers count as people, unless a test adds a chain.
struct FakeProcessTable: ProcessTable {
    var entries: [Int32: ProcessEntry] = [:]

    /// `chain` from the caller up: `[(200, "sh"), (100, "claude")]` makes 200 a child of 100, and 100 a child of launchd.
    init(_ chain: [(pid: Int32, name: String)] = []) {
        for (index, link) in chain.enumerated() {
            let parent = index + 1 < chain.count ? chain[index + 1].pid : 1
            entries[link.pid] = ProcessEntry(pid: link.pid, parent: parent, name: link.name)
        }
    }

    func entry(_ pid: Int32) -> ProcessEntry? { entries[pid] }
}

/// Answers lid asks from a script, or holds them until the test resolves them.
@MainActor
final class FakeLidApprover: LidApproving {
    struct Call: Equatable {
        let leaseID: String
        let agent: String
        let body: String
    }

    /// The answers to give, in order; `.timeout` once they run out.
    var answers: [LidAnswer] = []
    /// When true, each ask waits for `resolve(_:with:)`, showing as pending meanwhile.
    var holds = false
    /// When true, each ask waits for `resolve(_:with:)` without ever showing as pending, like the center while it
    /// awaits notification permission.
    var holdsBeforePending = false
    var pending: Set<String> = []
    private(set) var calls: [Call] = []
    private var held: [String: [CheckedContinuation<LidAnswer, Never>]] = [:]

    func ask(leaseID: String, agent: String, body: String) async -> LidAnswer {
        calls.append(Call(leaseID: leaseID, agent: agent, body: body))
        guard holds || holdsBeforePending else { return answers.isEmpty ? .timeout : answers.removeFirst() }
        if holds { pending.insert(leaseID) }
        let answer = await withCheckedContinuation { held[leaseID, default: []].append($0) }
        if holds { pending.remove(leaseID) }
        return answer
    }

    /// Answers every held ask for `leaseID`.
    func resolve(_ leaseID: String, with answer: LidAnswer) {
        for continuation in held.removeValue(forKey: leaseID) ?? [] { continuation.resume(returning: answer) }
    }

    /// Waits until `count` asks have been made (or about 2 s pass).
    func waitForCalls(_ count: Int) async {
        for _ in 0..<2000 where calls.count < count {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

@MainActor
struct RequestFixture {
    let knobs = RequestKnobs()
    let engine: AwakeEngine
    let handler: RequestHandler
    let approver = FakeLidApprover()
    /// Records what `notify` posts.
    let poster = FakeNotificationPoster()
    /// Answers window asks, unless the fixture was made with a `windowCenter`.
    let windowApprover = FakeWindowApprover()
    let windowCenter: WindowApprovalCenter?
    let caller: Caller

    /// `table` is the caller's ancestry; `callerPID` is where agent detection starts.
    init(
        processes: any ProcessInspecting = AliveProcesses(), table: FakeProcessTable = FakeProcessTable(), callerPID: Int32 = 77,
        windowCenter: WindowApprovalCenter? = nil
    ) {
        let knobs = knobs
        caller = Caller(uid: 501, pid: callerPID)
        let engine = AwakeEngine(
            assertions: NullAssertions(), store: MemoryStore(), processes: processes,
            lid: LidController(helper: FakeLidHelper()), settings: { knobs.settings }, now: { knobs.clock }
        )
        self.engine = engine
        self.windowCenter = windowCenter
        handler = RequestHandler(
            engine: engine, settings: { knobs.settings }, helperStatus: { "enabled" },
            readHelperSleepDisabled: { knobs.helperSleepDisabled }, now: { knobs.clock },
            processes: table, approver: approver, updateSettings: { change in change(&knobs.settings) },
            notificationStatus: { knobs.notifications }, poster: poster,
            windowsState: { knobs.windowsState }, arranger: { knobs.arranger },
            windowApprover: windowCenter.map { $0 as any WindowApproving } ?? windowApprover
        )
    }

    var clock: Date { knobs.clock }

    func lease(_ id: String) -> Lease? {
        engine.leases.first { $0.id == id }
    }

    func send(_ args: RequestArgs) async -> Response {
        let operation: Op = switch args {
        case .acquire: .acquire
        case .renew: .renew
        case .release: .release
        case .status: .status
        case .hook: .hook
        case .notify: .notify
        case .winList: .winList
        case .winArrange: .winArrange
        case .winUndo: .winUndo
        case .winLayout: .winLayout
        }
        return await handler.handle(Request(v: 1, id: "r1", op: operation, args: args), from: caller)
    }

    func acquire(
        _ kind: AcquireKind, id: String? = nil, level: String? = nil, ttl: Double? = nil, watchPid: Int32? = nil,
        reason: String? = nil, agent: String? = nil
    ) async -> Response {
        await send(.acquire(AcquireArgs(kind: kind, id: id, level: level, ttl: ttl, watchPid: watchPid, reason: reason, agent: agent)))
    }

    func renew(_ id: String, ttl: Double? = nil) async -> Response {
        await send(.renew(RenewArgs(id: id, ttl: ttl)))
    }

    func release(_ kind: ReleaseKind, id: String? = nil, after: Double? = nil) async -> Response {
        await send(.release(ReleaseArgs(kind: kind, id: id, after: after)))
    }
}

func wireFailure(_ response: Response) -> WireError? {
    response.ok ? nil : response.error
}

func acquireResult(_ response: Response) -> MooringIPC.AcquireResult? {
    if case .acquire(let result)? = response.result { result } else { nil }
}

func releasedFlag(_ response: Response) -> Bool? {
    if case .release(let result)? = response.result { result.released } else { nil }
}

func renewedLease(_ response: Response) -> LeaseInfo? {
    if case .renew(let info)? = response.result { info } else { nil }
}

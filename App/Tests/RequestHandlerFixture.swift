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
}

@MainActor
struct RequestFixture {
    let knobs = RequestKnobs()
    let engine: AwakeEngine
    let handler: RequestHandler
    let caller = Caller(uid: 501, pid: 77)

    init(processes: any ProcessInspecting = AliveProcesses()) {
        let knobs = knobs
        let engine = AwakeEngine(
            assertions: NullAssertions(), store: MemoryStore(), processes: processes,
            lid: LidController(helper: FakeLidHelper()), settings: { knobs.settings }, now: { knobs.clock }
        )
        self.engine = engine
        handler = RequestHandler(
            engine: engine, settings: { knobs.settings }, helperStatus: { "enabled" },
            readHelperSleepDisabled: { knobs.helperSleepDisabled }, now: { knobs.clock }
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

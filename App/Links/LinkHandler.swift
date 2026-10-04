import AwakeKit
import Foundation
import MooringIPC

/// Carries out `mooring://` links from Raycast, Alfred and scripts as requests from the app that sent them, which is
/// always an agent for the lid rules. A link has no reply channel, so what goes wrong is posted as a notification.
@MainActor
final class LinkHandler {
    /// The least time between two error notifications.
    static let errorInterval: TimeInterval = 10
    static let errorTitle = "Mooring couldn't use that link"
    /// The agent name of a link with no sender, or whose sender has no name.
    static let unnamedSender = "A link"

    private let gate: HandlerGate
    private let poster: any NotificationPosting
    private let appName: (Int32) -> String?
    private let now: () -> Date
    private var lastError: Date?

    /// `appName` gives a process's localized application name, such as "Raycast".
    init(gate: HandlerGate, poster: any NotificationPosting, appName: @escaping (Int32) -> String?, now: @escaping () -> Date = Date.init) {
        self.gate = gate
        self.poster = poster
        self.appName = appName
        self.now = now
    }

    /// Parses and carries out `url`, sent by `senderPID`. Returns once the request is answered, which for lid mode
    /// with no end can be after the person answers; the session starts without lid meanwhile.
    func open(_ url: URL, senderPID: Int32?) async {
        let action: LinkAction
        switch MooringLink.parse(url) {
        case .success(let parsed): action = parsed
        case .failure(let error):
            await report(error.message)
            return
        }
        // With no sender, the pid is Mooring's own, whose name isn't the caller's.
        let name = senderPID.flatMap(appName).map(CallerPolicy.cleanAgentName).flatMap { $0.isEmpty ? nil : $0 }
        let caller = Caller(uid: getuid(), pid: senderPID ?? getpid(), identity: .agent(name ?? Self.unnamedSender))
        let handler = await gate.handler()
        let response: Response
        switch action {
        case .on(let level, let duration, let reason):
            response = await turnOn(level: level, duration: duration, reason: reason, handler: handler, caller: caller)
        case .off:
            response = await turnOff(handler: handler, caller: caller)
        case .toggle(let level, let duration, let reason):
            let status = await send(.status, .status, to: handler, from: caller)
            if case .status(let result)? = status.result, Self.menuSessionIsOn(result) {
                response = await turnOff(handler: handler, caller: caller)
            } else {
                response = await turnOn(level: level, duration: duration, reason: reason, handler: handler, caller: caller)
            }
        }
        // A guardrail leaves the session on but paused, and has its own notice.
        if let error = response.error, error.code != .guardrail {
            await report(error.message)
        }
    }

    /// Whether the menu session, the menu's own lease or a picked app's, is live.
    private static func menuSessionIsOn(_ status: StatusResult) -> Bool {
        status.leases.contains { $0.id == AwakeEngine.menuLeaseID || $0.id.hasPrefix("app-") }
    }

    private func turnOn(
        level: String?, duration: TimeInterval?, reason: String?, handler: RequestHandler, caller: Caller
    ) async -> Response {
        let args = AcquireArgs(kind: .on, id: nil, level: level, ttl: duration, watchPid: nil, reason: reason, agent: nil)
        return await send(.acquire, .acquire(args), to: handler, from: caller)
    }

    private func turnOff(handler: RequestHandler, caller: Caller) async -> Response {
        await send(.release, .release(ReleaseArgs(kind: .off, id: nil, after: nil)), to: handler, from: caller)
    }

    private func send(_ operation: Op, _ args: RequestArgs, to handler: RequestHandler, from caller: Caller) async -> Response {
        let request = Request(v: WireProtocol.version, id: UUID().uuidString, op: operation, args: args)
        return await handler.handle(request, from: caller)
    }

    /// Posts `message`, unless an error was posted less than `errorInterval` ago.
    private func report(_ message: String) async {
        let current = now()
        if let lastError, current.timeIntervalSince(lastError) < Self.errorInterval { return }
        // Recorded before the first suspension, so two links at once can't both post.
        lastError = current
        guard await poster.authorize() else { return }
        _ = await poster.post(id: "link-error-\(UUID().uuidString)", title: Self.errorTitle, body: message, userInfo: [:], category: nil)
    }
}

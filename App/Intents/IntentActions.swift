import AppIntents
import AwakeKit
import Foundation
import MooringIPC

/// The level a Shortcuts action asks for, in the words the menu uses.
enum IntentLevel: String, AppEnum {
    case normal, display, lid

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Level"
    static let caseDisplayRepresentations: [IntentLevel: DisplayRepresentation] = [
        .normal: "Normal",
        .display: "Keep display on",
        .lid: "Keep awake with lid closed"
    ]

    /// The level name on the wire.
    var wire: String {
        switch self {
        case .normal: "system"
        case .display: "display"
        case .lid: "lid"
        }
    }
}

/// What a Shortcuts action can't do. `LocalizedError` is what Shortcuts shows.
enum IntentError: Error, Equatable, LocalizedError {
    /// The request was refused; `message` is the app's reason.
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

/// What the Shortcuts, Siri and Spotlight actions do. They are trusted like the menu, since a person runs them, and
/// go through the same request handler as `mooring on` and `mooring off`. The intents' `perform()` only call this.
@MainActor
final class IntentActions {
    static let shared = IntentActions()

    /// Where an action waits for the handler. The app hands its handler to the shared actions' gate, so an action that
    /// runs before the app has set itself up (a Shortcut that launches it) waits rather than fails.
    let gate: HandlerGate

    init(gate: HandlerGate = HandlerGate()) {
        self.gate = gate
    }

    private let caller = Caller(uid: getuid(), pid: getpid(), identity: .person)

    /// Turns the menu session on for `duration` seconds, or until turned off. With no `level` it keeps the running
    /// session's level, else the click level, as `mooring on` does without `--level`. Returns the text for the dialog:
    /// the status summary, or the guardrail that holds the session back (it is on, but paused).
    func keepAwake(duration: TimeInterval?, level: IntentLevel?) async throws -> String {
        let handler = await gate.handler()
        // An empty Duration is "until turned off", not the menu click's duration.
        let args = AcquireArgs(
            kind: .on, id: nil, level: level?.wire, ttl: duration, watchPid: nil, reason: nil, agent: nil,
            untilOff: duration == nil ? true : nil
        )
        let response = await send(.acquire, .acquire(args), to: handler)
        if let error = response.error {
            if error.code == .guardrail { return error.message }
            throw IntentError.failed(error.message)
        }
        return try await statusResult(handler).summary
    }

    /// Ends the menu session.
    func letSleep() async throws {
        let handler = await gate.handler()
        let response = await send(.release, .release(ReleaseArgs(kind: .off, id: nil, after: nil)), to: handler)
        if let error = response.error { throw IntentError.failed(error.message) }
    }

    func status() async throws -> AwakeStatusEntity {
        AwakeStatusEntity(try await statusResult(await gate.handler()))
    }

    private func statusResult(_ handler: RequestHandler) async throws -> StatusResult {
        let response = await send(.status, .status, to: handler)
        if let error = response.error { throw IntentError.failed(error.message) }
        guard case .status(let result)? = response.result else { throw IntentError.failed("Mooring gave no status") }
        return result
    }

    private func send(_ operation: Op, _ args: RequestArgs, to handler: RequestHandler) async -> Response {
        let request = Request(v: WireProtocol.version, id: UUID().uuidString, op: operation, args: args)
        return await handler.handle(request, from: caller)
    }
}

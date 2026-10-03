/// Hands out the request handler once it exists. A link can arrive with the launch, before the engine and handler
/// are built; its request waits here instead of being lost.
@MainActor
final class HandlerGate {
    private var ready: RequestHandler?
    private var waiting: [CheckedContinuation<RequestHandler, Never>] = []

    /// Makes `handler` the one handed out, and serves every request already waiting for it.
    func set(_ handler: RequestHandler) {
        ready = handler
        let resumed = waiting
        waiting = []
        for continuation in resumed { continuation.resume(returning: handler) }
    }

    /// The handler, waiting for `set` if it hasn't been called yet.
    func handler() async -> RequestHandler {
        if let ready { return ready }
        return await withCheckedContinuation { waiting.append($0) }
    }
}

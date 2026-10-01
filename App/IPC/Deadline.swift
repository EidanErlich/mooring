import Foundation
import os

/// `operation`'s result, or nil when it hasn't finished within `limit`. A late operation keeps running
/// and its result is dropped, so a call that ignores cancellation (like an XPC reply) can't hold up the caller.
func withDeadline<T: Sendable>(_ limit: Duration, _ operation: @escaping @Sendable () async -> T?) async -> T? {
    await withCheckedContinuation { continuation in
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let finish: @Sendable (T?) -> Void = { value in
            let isFirst = resumed.withLock { done -> Bool in
                defer { done = true }
                return !done
            }
            if isFirst { continuation.resume(returning: value) }
        }
        let work = Task { finish(await operation()) }
        Task {
            try? await Task.sleep(for: limit)
            work.cancel()
            finish(nil)
        }
    }
}

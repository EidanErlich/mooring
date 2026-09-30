import AwakeKit
import Foundation
import Testing

@MainActor
struct ProcessesTests {
    @Test func startTimeOfSelfIsInThePast() throws {
        let start = try #require(SystemProcesses().startTime(of: getpid()))
        #expect(start < Date())
    }

    @Test func startTimeOfMissingProcessIsNil() throws {
        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try finished.run()
        finished.waitUntilExit()
        #expect(SystemProcesses().startTime(of: finished.processIdentifier) == nil)
    }

    @Test func exitWatchFiresWhenProcessExits() async throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["0.3"]
        try sleeper.run()
        let processes = SystemProcesses()

        let fired = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var resumed = false
            let finish: @MainActor (Bool) -> Void = { value in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }
            let watch = processes.watchExit(of: sleeper.processIdentifier) { finish(true) }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                watch.cancel()
                finish(false)
            }
        }
        #expect(fired)
    }
}

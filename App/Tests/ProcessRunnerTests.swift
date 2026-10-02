import Foundation
import Testing
@testable import Mooring

struct ProcessRunnerTests {
    @Test func runnerCollectsOutputOfAFastCommand() {
        let result = ProcessRunner(timeout: 5).run(["/bin/sh", "-c", "echo out; echo err >&2; exit 3"])
        #expect(result.status == 3)
        #expect(String(bytes: result.stdout, encoding: .utf8) == "out\n")
        #expect(result.stderr == "err\n")
    }

    @Test func runnerReturnsWithinTheLimitWhenAChildHoldsThePipe() {
        // Two grandchildren inherit the pipes and outlive the shell, so EOF never arrives.
        let script = "sleep 30 & echo \"pid $!\"; sleep 30 & echo \"pid $!\"; echo started; wait"
        let start = Date()
        let result = ProcessRunner(timeout: 1).run(["/bin/sh", "-c", script])
        let elapsed = Date().timeIntervalSince(start)
        let text = String(bytes: result.stdout, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") where line.hasPrefix("pid ") {
            if let pid = Int32(line.dropFirst(4)) { kill(pid, SIGKILL) }
        }
        #expect(elapsed < 4)
        #expect(result.status == 124)
        #expect(text.contains("started"))
        #expect(result.stderr.contains("Timed out"))
    }

    @Test func runnerReturnsWhenTheCommandExitsButAChildKeepsThePipe() {
        let start = Date()
        let result = ProcessRunner(timeout: 5).run(["/bin/sh", "-c", "sleep 30 & echo \"pid $!\"; echo started"])
        let elapsed = Date().timeIntervalSince(start)
        let text = String(bytes: result.stdout, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") where line.hasPrefix("pid ") {
            if let pid = Int32(line.dropFirst(4)) { kill(pid, SIGKILL) }
        }
        #expect(elapsed < 4)
        #expect(result.status == 0)
        #expect(text.contains("started"))
    }
}

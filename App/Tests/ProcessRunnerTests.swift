import Foundation
import Testing
@testable import Mooring

struct ProcessRunnerTests {
    @Test func runnerPutsTheToolsFolderOnPath() {
        // `node` sits next to an npm-installed `claude`, so the command's own folder must lead PATH.
        let result = ProcessRunner(timeout: 5).run(["/bin/sh", "-c", "echo $PATH"])
        let path = String(bytes: result.stdout, encoding: .utf8) ?? ""
        #expect(path.hasPrefix("/bin:"))
        #expect(path.contains(":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"))
    }

    @Test func runnerKeepsTheRestOfTheEnvironment() {
        setenv("MOORING_RUNNER_TEST", "kept", 1)
        let result = ProcessRunner(timeout: 5).run(["/bin/sh", "-c", "echo $MOORING_RUNNER_TEST"])
        #expect(String(bytes: result.stdout, encoding: .utf8) == "kept\n")
    }

    @Test func loginShellLookupTakesTheLastAbsoluteLine() {
        struct Fixed: ToolRunning {
            func run(_ argv: [String]) -> ToolResult {
                ToolResult(status: 0, stdout: Data("Welcome to zsh\n/opt/banner/path\n/Users/me/.local/bin/claude\nbye\n".utf8))
            }
        }
        #expect(ClaudePluginInstaller.loginShellLookup(runner: Fixed()) == "/Users/me/.local/bin/claude")
        struct NoPath: ToolRunning {
            func run(_ argv: [String]) -> ToolResult { ToolResult(status: 0, stdout: Data("claude: aliased\n".utf8)) }
        }
        #expect(ClaudePluginInstaller.loginShellLookup(runner: NoPath()) == nil)
    }

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

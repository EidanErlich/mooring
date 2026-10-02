import Darwin
import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

/// Spawns real children. Serialized because each `anchor --` run ignores INT, TERM and HUP in this process
/// for a moment, and a child spawned meanwhile would inherit that.
@Suite(.serialized) struct AnchorTests {
    @Test func passesThroughExitCode() throws {
        let run = AnchorRun(command: ["sh", "-c", "exit 7"])
        #expect(try run.start() > 0)
        #expect(run.wait() == 7)
    }

    @Test func forwardsSignals() throws {
        let run = AnchorRun(command: ["sleep", "5"])
        _ = try run.start()
        let started = ContinuousClock.now
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { run.forward(SIGINT) }
        #expect(run.wait() == 130)
        #expect(ContinuousClock.now - started < .milliseconds(1500))
    }

    @Test func interruptIsNotForwardedWhenForeground() async throws {
        let run = AnchorRun(command: ["sleep", "2"])
        let pid = try run.start()
        SignalRelay(child: run, isForegroundOfTerminal: { true }).deliver(SIGINT)
        try await Task.sleep(for: .milliseconds(300))
        var status: Int32 = 0
        #expect(waitpid(pid, &status, WNOHANG) == 0)
        run.forward(SIGKILL)
        #expect(run.wait() == 128 + SIGKILL)
    }

    @Test func interruptIsForwardedWhenNotForeground() throws {
        let run = AnchorRun(command: ["sleep", "2"])
        _ = try run.start()
        SignalRelay(child: run, isForegroundOfTerminal: { false }).deliver(SIGINT)
        #expect(run.wait() == 130)
    }

    @Test func terminateIsAlwaysForwarded() throws {
        let run = AnchorRun(command: ["sleep", "2"])
        _ = try run.start()
        SignalRelay(child: run, isForegroundOfTerminal: { true }).deliver(SIGTERM)
        #expect(run.wait() == 143)
    }

    @Test func missingCommandFailsToStart() {
        let run = AnchorRun(command: ["mooring-test-no-such-command"])
        #expect(throws: (any Error).self) { try run.start() }
    }

    @Test func anchorCommandChecksReachabilityFirst() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let marker = folder + "/marker"
        let harness = Harness(client: RecordingClient(reply: .failure(.unreachable)))

        #expect(await harness.run(["anchor", "--", "touch", marker]) == 3)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: marker))
        #expect(harness.client.requests.map(\.op) == [.status])
        #expect(harness.capture.stderr == "mooring: Mooring isn't running and couldn't be started\n")
    }

    @Test func anchorCommandDoesNotStartWhenTheAppIsNotAnswering() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        for error in [CLIError.noAnswer, .blocked] {
            let marker = folder + "/marker-\(error)"
            let harness = Harness(client: RecordingClient(reply: .failure(error)))
            #expect(await harness.run(["anchor", "--", "touch", marker]) == 3)
            try await Task.sleep(for: .milliseconds(200))
            #expect(!FileManager.default.fileExists(atPath: marker))
            #expect(harness.client.requests.map(\.op) == [.status])
            #expect(harness.capture.stderr.hasPrefix("mooring: "))
        }
    }

    @Test func anchorCommandAcquiresWithTheChildPid() async throws {
        let harness = Harness()
        #expect(await harness.run(["anchor", "--level", "display", "--agent", "Make", "--", "sh", "-c", "exit 5"]) == 5)
        let requests = harness.client.requests
        #expect(requests.map(\.op) == [.status, .acquire])
        guard case .acquire(let args)? = requests.last?.args else {
            Issue.record("expected an acquire")
            return
        }
        #expect(args.kind == .anchor)
        #expect((args.watchPid ?? 0) > 0)
        #expect(args.reason == "sh -c exit 5")
        #expect(args.level == "display")
        #expect(args.agent == "Make")
        #expect(harness.client.lastLaunch == true)
        #expect(harness.capture.stdout.isEmpty)
        #expect(harness.capture.stderr.isEmpty)
    }

    @Test func anchorCommandForwardsTermToTheChild() async throws {
        let harness = Harness()
        let started = ContinuousClock.now
        async let code = harness.run(["anchor", "--", "sleep", "5"])
        // Forwarding is in place before the acquire goes out, so once it's recorded a TERM here reaches the child.
        for _ in 0..<200 where !harness.client.requests.contains(where: { $0.op == .acquire }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        // Without the acquire, nothing is forwarding yet and the TERM would end the whole test run.
        try #require(harness.client.requests.contains { $0.op == .acquire })
        kill(getpid(), SIGTERM)
        #expect(await code == 128 + SIGTERM)
        #expect(ContinuousClock.now - started < .milliseconds(1500))
    }

    @Test func givenReasonIsKept() async {
        let harness = Harness()
        #expect(await harness.run(["anchor", "--reason", "render", "--json", "--", "true"]) == 0)
        guard case .acquire(let args)? = harness.client.lastRequest?.args else {
            Issue.record("expected an acquire")
            return
        }
        #expect(args.reason == "render")
        #expect(harness.capture.stdout.isEmpty)
    }

    @Test func anchorAtALidLevelAcquiresThroughTheLidClient() async {
        let harness = Harness()
        #expect(await harness.run(["anchor", "--level", "lid", "--", "sh", "-c", "exit 0"]) == 0)
        #expect(harness.client.requests.map(\.op) == [.status])
        #expect(harness.lidClient.requests.map(\.op) == [.acquire])
    }

    @Test func guardrailIsAWarning() async {
        let harness = Harness(lidClient: RecordingClient(reply: .success(.failure(id: "r", .guardrail, "Lid mode paused: battery low"))))
        #expect(await harness.run(["anchor", "--level", "lid", "--", "sh", "-c", "exit 0"]) == 0)
        #expect(harness.capture.stderr == "mooring: Lid mode paused: battery low\n")
    }

    @Test func failedAcquireRunsWithoutTheLease() async {
        let harness = Harness(client: RecordingClient(reply: .success(.failure(id: "r", .internal, "boom"))))
        #expect(await harness.run(["anchor", "--", "sh", "-c", "exit 4"]) == 4)
        #expect(harness.capture.stderr == "mooring: couldn't anchor (boom); running without it\n")
    }

    @Test func missingCommandExits127() async {
        let harness = Harness()
        #expect(await harness.run(["anchor", "--", "mooring-test-no-such-command"]) == 127)
        #expect(harness.capture.stderr == "mooring: mooring-test-no-such-command: No such file or directory\n")
        #expect(harness.client.requests.map(\.op) == [.status])
    }

    @Test func pidAndCommandIsAUsageError() async {
        let harness = Harness()
        #expect(await harness.run(["anchor", "--pid", "5", "--", "sleep", "1"]) == 1)
        #expect(harness.capture.stderr == "mooring: Use either --pid or -- <command>\n")
        #expect(harness.client.requests.isEmpty)
    }
}

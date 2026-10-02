import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

private func status(
    leases: [LeaseInfo] = [], power: PowerInfo = PowerInfo(onAC: false, batteryPercent: 64), lidClosed: Bool? = false,
    suspensions: [String] = ["lowBatteryLid"]
) -> StatusResult {
    StatusResult(
        summary: "On · lid mode · 1h 12m left", effective: LevelInfo(system: true, display: false, lid: false),
        systemAssertion: true, displayAssertion: false, lidSleepDisabled: false, helperSleepDisabled: nil, wantsLid: true,
        leases: leases, power: power, thermal: "nominal", lidClosed: lidClosed, helper: "enabled", suspensions: suspensions,
        notifications: nil, agentLidApproval: nil
    )
}

private let threeLeases = [
    leaseInfo(
        id: "menu", owner: OwnerInfo(kind: "menu", name: "Menu bar"), reason: "Turned on from the menu bar",
        level: "lid", expiresAt: fixedNow.addingTimeInterval(72 * 60), ttl: 4320
    ),
    leaseInfo(id: "cli", owner: OwnerInfo(kind: "cli", name: "Terminal"), reason: "mooring on"),
    leaseInfo(
        id: "churn", owner: OwnerInfo(kind: "agent", name: "Claude Code"), reason: "Churn analysis",
        expiresAt: fixedNow.addingTimeInterval(4 * 3600), watchPid: 80, ttl: 14_400
    )
]

@Test func humanStatusLayout() {
    let text = StatusText.human(status(leases: threeLeases), now: fixedNow)
    let expected = """
    On · lid mode · 1h 12m left
    Leases (3)
      Menu bar      Turned on from the menu bar   1h 12m left
      Terminal      mooring on                    until turned off
      Claude Code   Churn analysis                while running · 4h cap
    Battery 64% · Thermal nominal · Lid open · Helper enabled
    Paused: lid mode (battery low)

    """
    #expect(text == expected)
}

@Test func statusWithNoLeasesOnPower() {
    let text = StatusText.human(
        status(leases: [], power: PowerInfo(onAC: true, batteryPercent: 100), lidClosed: nil, suspensions: []), now: fixedNow
    )
    #expect(text == """
    On · lid mode · 1h 12m left
    No leases
    On power · Thermal nominal · Helper enabled

    """)
}

@Test func statusWithoutABatteryPercentAndEverySuspension() {
    let text = StatusText.human(
        status(
            leases: [], power: PowerInfo(onAC: false, batteryPercent: nil), lidClosed: true,
            suspensions: ["lidNeedsAC", "thermal", "lowBatteryLid", "lowBatteryAll"]
        ), now: fixedNow
    )
    #expect(text.contains("\nBattery · Thermal nominal · Lid closed · Helper enabled\n"))
    #expect(text.hasSuffix(
        "Paused: everything (battery low), lid mode (battery low), lid mode (Mac too warm), lid mode (needs power)\n"
    ))
}

@Test func remainingRoundsUpToWholeMinutes() {
    #expect(CLIText.remaining(0) == "0m")
    #expect(CLIText.remaining(-30) == "0m")
    #expect(CLIText.remaining(1) == "1m")
    #expect(CLIText.remaining(59 * 60 + 1) == "1h")
    #expect(CLIText.remaining(4 * 3600 - 0.4) == "4h")
    #expect(CLIText.remaining(72 * 60) == "1h 12m")
}

@Test func jsonPrintsTheResult() async throws {
    let harness = Harness(client: RecordingClient(reply: .success(.success(id: "r", .status(status(leases: threeLeases))))))
    #expect(await harness.run(["status", "--json"]) == 0)
    let object = try #require(try JSONSerialization.jsonObject(with: Data(harness.capture.stdout.utf8)) as? [String: Any])
    #expect((object["leases"] as? [Any])?.count == 3)
    #expect(object["summary"] as? String == "On · lid mode · 1h 12m left")
    #expect(object["ok"] == nil)
    #expect(harness.capture.stdout.hasSuffix("}\n"))
    #expect(harness.capture.stderr.isEmpty)
}

@Test func jsonErrorsGoToStdout() async throws {
    let harness = Harness(client: RecordingClient(reply: .success(.failure(id: "r", .guardrail, "Lid mode paused: battery low"))))
    #expect(await harness.run(["on", "--level", "lid", "--json"]) == 2)
    let text = harness.capture.stdout
    #expect(text.contains(#""ok":false"#))
    #expect(text.contains(#""code":"guardrail""#))
    #expect(harness.capture.stderr.isEmpty)
}

@Test func jsonPrintsAcquireResultsAndReleases() async throws {
    let harness = Harness(client: RecordingClient(reply: .success(acquired(leaseInfo(), clamped: true))))
    #expect(await harness.run(["lease", "acquire", "job", "--ttl", "5m", "--json"]) == 0)
    let object = try #require(try JSONSerialization.jsonObject(with: Data(harness.capture.stdout.utf8)) as? [String: Any])
    #expect(object["clamped"] as? Bool == true)
    #expect((object["lease"] as? [String: Any])?["id"] as? String == "job")

    let release = Harness(client: RecordingClient(reply: .success(.success(id: "r", .release(ReleaseResult(released: false))))))
    #expect(await release.run(["off", "--json"]) == 0)
    #expect(release.capture.stdout == #"{"released":false}"# + "\n")
}

@Test func acquireText() async {
    let turnedOn = Harness(client: RecordingClient(reply: .success(acquired(
        leaseInfo(id: "cli", level: "display,lid", expiresAt: fixedNow.addingTimeInterval(1800))
    ))))
    #expect(await turnedOn.run(["on"]) == 0)
    #expect(turnedOn.capture.stdout == "On · 30m left · screen on · lid mode\n")

    let forever = Harness(client: RecordingClient(reply: .success(acquired(leaseInfo(id: "cli", level: "system")))))
    _ = await forever.run(["on"])
    #expect(forever.capture.stdout == "On · until turned off\n")

    let anchor = Harness(client: RecordingClient(reply: .success(acquired(leaseInfo(id: "anchor-9", watchPid: 9)))))
    _ = await anchor.run(["anchor", "--pid", "9"])
    #expect(anchor.capture.stdout == "Anchored anchor-9 · while process 9 runs\n")

    let capped = Harness(client: RecordingClient(reply: .success(acquired(
        leaseInfo(expiresAt: fixedNow.addingTimeInterval(4 * 3600), watchPid: 9), clamped: true
    ))))
    _ = await capped.run(["lease", "acquire", "job", "--watch-pid", "9"])
    #expect(capped.capture.stdout == "Lease job · while process 9 runs · 4h cap (capped at 4h)\n")
}

@Test func leaseAcquireNamesTheWatchedProcess() async {
    let reply = acquired(leaseInfo(expiresAt: fixedNow.addingTimeInterval(4 * 3600), watchPid: 80))
    let harness = Harness(
        client: RecordingClient(reply: .success(reply)), table: FakeProcessTable([proc(80, 1, "claude")])
    )
    #expect(await harness.run(["lease", "acquire", "job", "--watch-pid", "80"]) == 0)
    #expect(harness.capture.stdout == "Lease job · while Claude Code (80) runs · 4h cap\n")

    let other = Harness(
        client: RecordingClient(reply: .success(reply)), table: FakeProcessTable([proc(80, 1, "make")])
    )
    _ = await other.run(["lease", "acquire", "job", "--watch-pid", "80"])
    #expect(other.capture.stdout == "Lease job · while make (80) runs · 4h cap\n")
}

@Test func anchorPidNamesTheWatchedProcess() async {
    let reply = acquired(leaseInfo(id: "anchor-80", watchPid: 80))
    let harness = Harness(
        client: RecordingClient(reply: .success(reply)), table: FakeProcessTable([proc(80, 1, "codex")])
    )
    #expect(await harness.run(["anchor", "--pid", "80"]) == 0)
    #expect(harness.capture.stdout == "Anchored anchor-80 · while Codex (80) runs\n")
}

@Test func watchedProcessNameLeavesJSONAndStatusAlone() async throws {
    let reply = acquired(leaseInfo(expiresAt: fixedNow.addingTimeInterval(600), watchPid: 80))
    let harness = Harness(
        client: RecordingClient(reply: .success(reply)), table: FakeProcessTable([proc(80, 1, "claude")])
    )
    _ = await harness.run(["lease", "acquire", "job", "--watch-pid", "80", "--json"])
    #expect(!harness.capture.stdout.contains("while"))
    #expect(!harness.capture.stdout.contains("(80)"))

    let lease = leaseInfo(expiresAt: fixedNow.addingTimeInterval(600), watchPid: 80)
    #expect(CLIText.timeText(lease, now: fixedNow) == "while running · 10m cap")
}

@Test func renewAndReleaseText() async {
    let renew = Harness(client: RecordingClient(reply: .success(.success(
        id: "r", .renew(leaseInfo(expiresAt: fixedNow.addingTimeInterval(600)))
    ))))
    _ = await renew.run(["lease", "renew", "job"])
    #expect(renew.capture.stdout == "Renewed job · 10m left\n")

    let released = Harness(client: RecordingClient(reply: .success(.success(id: "r", .release(ReleaseResult(released: true))))))
    _ = await released.run(["lease", "release", "job"])
    _ = await released.run(["off"])
    #expect(released.capture.stdout == "Released job\nOff\n")

    let gone = Harness(client: RecordingClient(reply: .success(.success(id: "r", .release(ReleaseResult(released: false))))))
    _ = await gone.run(["lease", "release", "job"])
    _ = await gone.run(["off"])
    #expect(gone.capture.stdout == "job wasn't active\nAlready off\n")
}

@Test func statusCommandPrintsTheBlock() async {
    let harness = Harness(client: RecordingClient(reply: .success(.success(id: "r", .status(status(leases: threeLeases))))))
    #expect(await harness.run(["status"]) == 0)
    #expect(harness.capture.stdout.hasPrefix("On · lid mode · 1h 12m left\nLeases (3)\n"))
    #expect(harness.capture.stdout.hasSuffix("Paused: lid mode (battery low)\n"))
}

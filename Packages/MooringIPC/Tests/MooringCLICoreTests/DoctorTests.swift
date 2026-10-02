import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

private func doctorStatus(helper: String = "enabled", helperSleepDisabled: Bool? = false, lidSleepDisabled: Bool = false) -> StatusResult {
    StatusResult(
        summary: "On · 1h left", effective: LevelInfo(system: true, display: false, lid: lidSleepDisabled),
        systemAssertion: true, displayAssertion: false, lidSleepDisabled: lidSleepDisabled,
        helperSleepDisabled: helperSleepDisabled, wantsLid: lidSleepDisabled, leases: [],
        power: PowerInfo(onAC: true, batteryPercent: 90), thermal: "nominal", lidClosed: false, helper: helper, suspensions: []
    )
}

/// A temp folder holding an executable `mooring`, removed when the value goes away.
private final class BinFolder {
    let path: String
    var binary: String { path + "/mooring" }

    init() throws {
        path = try makeTempFolder()
        FileManager.default.createFile(atPath: path + "/mooring", contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
    }

    deinit { try? FileManager.default.removeItem(atPath: path) }
}

/// The checks with the real symlink resolver.
private func runChecks(
    _ status: StatusResult?, pathEnv: String?, ownBinary: String, claude: ClaudeSnapshot? = nil
) -> [Doctor.Check] {
    Doctor.checks(status: status, pathEnv: pathEnv, ownBinary: ownBinary, resolve: Doctor.resolvePath, claude: claude)
}

private func plugin(_ id: String, version: String = "0.1.0", enabled: Bool = true) -> ClaudeCode.InstalledPlugin {
    ClaudeCode.InstalledPlugin(id: id, version: version, enabled: enabled, installPath: nil)
}

/// The plugin and version checks for a snapshot.
private func claudeChecks(_ claude: ClaudeSnapshot?) -> [Doctor.Check] {
    Array(Doctor.checks(status: nil, pathEnv: nil, ownBinary: "/nowhere/mooring", resolve: { $0 }, claude: claude).suffix(2))
}

private let pluginFix = "Settings → Awake → Agents → Install"

@Test func allPass() throws {
    let bin = try BinFolder()
    let checks = runChecks(doctorStatus(), pathEnv: "/nonexistent-dir:" + bin.path, ownBinary: bin.binary)
    #expect(checks == [
        Doctor.Check(name: "App", state: "pass", detail: "On · 1h left", fix: nil),
        Doctor.Check(name: "Command on PATH", state: "pass", detail: bin.binary, fix: nil),
        Doctor.Check(name: "Helper", state: "pass", detail: "enabled", fix: nil),
        Doctor.Check(name: "Lid sleep", state: "pass", detail: "matches", fix: nil),
        Doctor.Check(name: "Claude plugin", state: "skip", detail: "Claude Code not found", fix: nil),
        Doctor.Check(name: "Claude Code version", state: "skip", detail: "unknown", fix: nil)
    ])
}

@Test func symlinkOnPathCountsAsThisBinary() throws {
    let bin = try BinFolder()
    let link = try BinFolder()
    try FileManager.default.removeItem(atPath: link.binary)
    try FileManager.default.createSymbolicLink(atPath: link.binary, withDestinationPath: bin.binary)
    let checks = runChecks(doctorStatus(), pathEnv: link.path, ownBinary: bin.binary)
    #expect(checks[1] == Doctor.Check(name: "Command on PATH", state: "pass", detail: link.binary, fix: nil))
}

@Test func noAppFailsFirstCheck() throws {
    let bin = try BinFolder()
    let checks = runChecks(nil, pathEnv: bin.path, ownBinary: bin.binary)
    #expect(checks[0] == Doctor.Check(name: "App", state: "fail", detail: "not running", fix: "Open Mooring"))
    #expect(checks[1].state == "pass")
    #expect(checks[2] == Doctor.Check(name: "Helper", state: "skip", detail: "needs the app", fix: nil))
    #expect(checks[3] == Doctor.Check(name: "Lid sleep", state: "skip", detail: "needs the app", fix: nil))
}

@Test func pathMismatchFails() throws {
    let other = try BinFolder()
    let own = try BinFolder()
    let fix = "Settings → General → Install command-line tool, and add ~/.local/bin to PATH"
    let mismatch = runChecks(doctorStatus(), pathEnv: "\(other.path):\(own.path)", ownBinary: own.binary)
    #expect(mismatch[1] == Doctor.Check(name: "Command on PATH", state: "fail", detail: "\(other.binary) is another copy", fix: fix))

    let missing = runChecks(doctorStatus(), pathEnv: "/nonexistent-dir", ownBinary: own.binary)
    #expect(missing[1] == Doctor.Check(name: "Command on PATH", state: "fail", detail: "not found on PATH", fix: fix))
    let noPath = runChecks(doctorStatus(), pathEnv: nil, ownBinary: own.binary)
    #expect(noPath[1].detail == "not found on PATH")
}

@Test func helperNotApprovedFails() throws {
    let bin = try BinFolder()
    let checks = runChecks(doctorStatus(helper: "requiresApproval"), pathEnv: bin.path, ownBinary: bin.binary)
    #expect(checks[2] == Doctor.Check(
        name: "Helper", state: "fail", detail: "requiresApproval", fix: "Settings → Lid & Battery → Approve"
    ))
}

@Test func stuckLidSleepFails() throws {
    let bin = try BinFolder()
    let fix = "Quit and reopen Mooring to restore sleep"
    func lidCheck(_ status: StatusResult) -> Doctor.Check {
        runChecks(status, pathEnv: bin.path, ownBinary: bin.binary)[3]
    }
    #expect(lidCheck(doctorStatus(helperSleepDisabled: true, lidSleepDisabled: false))
        == Doctor.Check(name: "Lid sleep", state: "fail", detail: "stuck disabled", fix: fix))
    #expect(lidCheck(doctorStatus(helperSleepDisabled: false, lidSleepDisabled: true))
        == Doctor.Check(name: "Lid sleep", state: "fail", detail: "mismatch", fix: fix))
    #expect(lidCheck(doctorStatus(helperSleepDisabled: true, lidSleepDisabled: true)).state == "pass")
    #expect(lidCheck(doctorStatus(helperSleepDisabled: nil)).state == "skip")
}

@Test func pluginFromAppPasses() {
    let snapshot = ClaudeSnapshot(version: "2.1.285", plugins: [plugin("other@x"), plugin(ClaudeCode.appPluginID)], testedWith: "2.1")
    #expect(claudeChecks(snapshot)[0] == Doctor.Check(name: "Claude plugin", state: "pass", detail: "mooring@mooring-app 0.1.0", fix: nil))
}

@Test func pluginFromGitHubPasses() {
    let snapshot = ClaudeSnapshot(version: "2.1.285", plugins: [plugin(ClaudeCode.repoPluginID, version: "0.2.0")], testedWith: "2.1")
    #expect(claudeChecks(snapshot)[0] == Doctor.Check(name: "Claude plugin", state: "pass", detail: "mooring@mooring 0.2.0", fix: nil))
}

@Test func disabledPluginFails() {
    let snapshot = ClaudeSnapshot(version: "2.1.285", plugins: [plugin(ClaudeCode.appPluginID, enabled: false)], testedWith: nil)
    #expect(claudeChecks(snapshot)[0] == Doctor.Check(name: "Claude plugin", state: "fail", detail: "disabled", fix: pluginFix))
}

@Test func noPluginFails() {
    let expected = Doctor.Check(name: "Claude plugin", state: "fail", detail: "not installed", fix: pluginFix)
    #expect(claudeChecks(ClaudeSnapshot(version: "2.1.285", plugins: [plugin("other@x")], testedWith: nil))[0] == expected)
    #expect(claudeChecks(ClaudeSnapshot(version: "2.1.285", plugins: [], testedWith: nil))[0] == expected)
    // With no version either, nothing says `claude` works, so the missing list reads the same.
    #expect(claudeChecks(ClaudeSnapshot(version: nil, plugins: nil, testedWith: nil))[0] == expected)
}

@Test func failedPluginListSkipsInsteadOfClaimingNotInstalled() {
    let snapshot = ClaudeSnapshot(version: "2.1.285", plugins: nil, testedWith: nil)
    #expect(claudeChecks(snapshot)[0] == Doctor.Check(
        name: "Claude plugin", state: "skip", detail: "couldn't check (claude plugin list failed)", fix: nil
    ))
}

@Test func bothCopiesPassWhenEitherIsEnabled() {
    func check(app: Bool, repo: Bool) -> Doctor.Check {
        let plugins = [
            plugin(ClaudeCode.appPluginID, enabled: app), plugin(ClaudeCode.repoPluginID, version: "0.2.0", enabled: repo)
        ]
        return claudeChecks(ClaudeSnapshot(version: "2.1.285", plugins: plugins, testedWith: nil))[0]
    }
    #expect(check(app: false, repo: true) == Doctor.Check(name: "Claude plugin", state: "pass", detail: "mooring@mooring 0.2.0", fix: nil))
    #expect(check(app: true, repo: false).detail == "mooring@mooring-app 0.1.0")
    #expect(check(app: true, repo: false).state == "pass")
    #expect(check(app: true, repo: true).detail == "mooring@mooring-app 0.1.0")
    #expect(check(app: false, repo: false) == Doctor.Check(name: "Claude plugin", state: "fail", detail: "disabled", fix: pluginFix))
}

@Test func noClaudeSkips() {
    #expect(claudeChecks(nil) == [
        Doctor.Check(name: "Claude plugin", state: "skip", detail: "Claude Code not found", fix: nil),
        Doctor.Check(name: "Claude Code version", state: "skip", detail: "unknown", fix: nil)
    ])
}

@Test func versionMatchPasses() {
    let snapshot = ClaudeSnapshot(version: "2.1.285", plugins: [], testedWith: "2.1")
    #expect(claudeChecks(snapshot)[1] == Doctor.Check(name: "Claude Code version", state: "pass", detail: "2.1.285", fix: nil))
}

@Test func versionMismatchSkips() {
    let snapshot = ClaudeSnapshot(version: "2.2.0", plugins: [], testedWith: "2.1")
    #expect(claudeChecks(snapshot)[1] == Doctor.Check(
        name: "Claude Code version", state: "skip", detail: "tested with 2.1; you have 2.2.0", fix: nil
    ))
}

@Test func versionUnknownSkips() {
    let skip = Doctor.Check(name: "Claude Code version", state: "skip", detail: "unknown", fix: nil)
    #expect(claudeChecks(ClaudeSnapshot(version: nil, plugins: [], testedWith: "2.1"))[1] == skip)
    #expect(claudeChecks(ClaudeSnapshot(version: "2.1.285", plugins: [], testedWith: nil))[1] == skip)
    // A version string that isn't major.minor can't be compared either.
    #expect(claudeChecks(ClaudeSnapshot(version: "banana", plugins: [], testedWith: "2.1"))[1] == skip)
}

@Test func humanFormatUsesMarks() {
    let text = Doctor.human([
        Doctor.Check(name: "App", state: "pass", detail: "On · 1h left", fix: nil),
        Doctor.Check(name: "Command on PATH", state: "fail", detail: "not found on PATH", fix: "Install it"),
        Doctor.Check(name: "Claude plugin", state: "skip", detail: "Claude Code not found", fix: nil)
    ])
    #expect(text == """
    ✓ App              On · 1h left
    ✗ Command on PATH  not found on PATH — Install it
    – Claude plugin    Claude Code not found

    """)
}

@Test func humanOutputListsSixChecks() async throws {
    let bin = try BinFolder()
    let snapshot = ClaudeSnapshot(version: "2.2.0", plugins: [plugin(ClaudeCode.appPluginID)], testedWith: "2.1")
    let harness = Harness(
        client: RecordingClient(reply: .success(.success(id: "r", .status(doctorStatus())))),
        ownBinaryPath: bin.binary, pathEnv: bin.path, claude: snapshot
    )
    #expect(await harness.run(["doctor"]) == 0)
    let lines = harness.capture.stdout.split(separator: "\n").map(String.init)
    #expect(lines.count == 6)
    #expect(lines[4] == "✓ Claude plugin        mooring@mooring-app 0.1.0")
    #expect(lines[5] == "– Claude Code version  tested with 2.1; you have 2.2.0")
}

@Test func versionMismatchDoesNotFailDoctor() async throws {
    let bin = try BinFolder()
    let newer = ClaudeSnapshot(version: "2.2.0", plugins: [plugin(ClaudeCode.appPluginID)], testedWith: "2.1")
    let harness = Harness(
        client: RecordingClient(reply: .success(.success(id: "r", .status(doctorStatus())))),
        ownBinaryPath: bin.binary, pathEnv: bin.path, claude: newer
    )
    #expect(await harness.run(["doctor"]) == 0)
    #expect(harness.capture.stdout.contains("– Claude Code version"))
    #expect(!harness.capture.stdout.contains("✗"))
}

@Test func doctorExitCodes() async throws {
    let bin = try BinFolder()
    let healthy = Harness(
        client: RecordingClient(reply: .success(.success(id: "r", .status(doctorStatus())))),
        ownBinaryPath: bin.binary, pathEnv: bin.path
    )
    #expect(await healthy.run(["doctor"]) == 0)
    #expect(healthy.capture.stdout.hasPrefix("✓ App  "))
    #expect(healthy.client.lastLaunch == false)
    #expect(healthy.client.lastRequest?.op == .status)

    let down = Harness(client: RecordingClient(reply: .failure(.unreachable)), ownBinaryPath: bin.binary, pathEnv: bin.path)
    #expect(await down.run(["doctor"]) == 1)
    #expect(down.capture.stdout.hasPrefix("✗ App  "))
    #expect(down.capture.stdout.contains("not running — Open Mooring\n"))
}

@Test func doctorNamesWhyTheAppIsDown() async throws {
    let bin = try BinFolder()
    let cases: [(CLIError, String)] = [
        (.unreachable, "not running"), (.noAnswer, "didn't answer"), (.blocked, "permission denied")
    ]
    for (error, detail) in cases {
        let harness = Harness(client: RecordingClient(reply: .failure(error)), ownBinaryPath: bin.binary, pathEnv: bin.path)
        #expect(await harness.run(["doctor"]) == 1)
        #expect(harness.capture.stdout.contains("\(detail) — Open Mooring\n"))
    }
}

@Test func doctorSaysWhenTheAppAnsweredWithAnError() async throws {
    let bin = try BinFolder()
    let harness = Harness(
        client: RecordingClient(reply: .success(.failure(id: "r", .internal, "boom"))), ownBinaryPath: bin.binary, pathEnv: bin.path
    )
    #expect(await harness.run(["doctor"]) == 1)
    #expect(harness.capture.stdout.contains("answered with an error: boom — Quit and reopen Mooring\n"))
    #expect(!harness.capture.stdout.contains("not running"))
}

@Test func doctorJSON() async throws {
    let bin = try BinFolder()
    let harness = Harness(
        client: RecordingClient(reply: .success(.success(id: "r", .status(doctorStatus(helper: "notRegistered"))))),
        ownBinaryPath: bin.binary, pathEnv: bin.path
    )
    #expect(await harness.run(["doctor", "--json"]) == 1)
    let text = harness.capture.stdout
    #expect(text.hasPrefix(#"{"checks":[{"detail":"On · 1h left","name":"App","state":"pass"}"#))
    #expect(text.hasSuffix("]}\n"))
    #expect(text.contains(#""detail":"\#(bin.binary)""#))
    #expect(text.filter { $0 == "\n" }.count == 1)
    let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: [[String: String]]])
    #expect(object["checks"]?.count == 6)
    #expect(object["checks"]?[2]["fix"] == "Settings → Lid & Battery → Approve")
}

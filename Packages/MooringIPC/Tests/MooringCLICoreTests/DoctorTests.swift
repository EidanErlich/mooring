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
private func runChecks(_ status: StatusResult?, pathEnv: String?, ownBinary: String) -> [Doctor.Check] {
    Doctor.checks(status: status, pathEnv: pathEnv, ownBinary: ownBinary, resolve: Doctor.resolvePath)
}

@Test func allPass() throws {
    let bin = try BinFolder()
    let checks = runChecks(doctorStatus(), pathEnv: "/nonexistent-dir:" + bin.path, ownBinary: bin.binary)
    #expect(checks == [
        Doctor.Check(name: "App", state: "pass", detail: "On · 1h left", fix: nil),
        Doctor.Check(name: "Command on PATH", state: "pass", detail: bin.binary, fix: nil),
        Doctor.Check(name: "Helper", state: "pass", detail: "enabled", fix: nil),
        Doctor.Check(name: "Lid sleep", state: "pass", detail: "matches", fix: nil),
        Doctor.Check(name: "Claude plugin", state: "skip", detail: "arrives in 2b", fix: nil)
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

@Test func pluginIsSkipped() throws {
    let checks = Doctor.checks(status: nil, pathEnv: nil, ownBinary: "/nowhere/mooring", resolve: { $0 })
    #expect(checks.last == Doctor.Check(name: "Claude plugin", state: "skip", detail: "arrives in 2b", fix: nil))
}

@Test func humanFormatUsesMarks() {
    let text = Doctor.human([
        Doctor.Check(name: "App", state: "pass", detail: "On · 1h left", fix: nil),
        Doctor.Check(name: "Command on PATH", state: "fail", detail: "not found on PATH", fix: "Install it"),
        Doctor.Check(name: "Claude plugin", state: "skip", detail: "arrives in 2b", fix: nil)
    ])
    #expect(text == """
    ✓ App              On · 1h left
    ✗ Command on PATH  not found on PATH — Install it
    – Claude plugin    arrives in 2b

    """)
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
    #expect(object["checks"]?.count == 5)
    #expect(object["checks"]?[2]["fix"] == "Settings → Lid & Battery → Approve")
}

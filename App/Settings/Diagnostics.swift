import AwakeKit
import Foundation
import IOKit.pwr_mgt

/// "Export diagnostics…" (docs/SPEC.md 1.10): leases, engine state, helper
/// status, this process's power assertions and recent logs, zipped. It never
/// runs pmset; SleepDisabled comes from the helper.
enum Diagnostics {
    @MainActor
    static func collect(
        engine: AwakeEngine, helperStatus: HelperStatus, sleepDisabled: Bool?,
        logs: () -> String = recentLogs
    ) -> [String: String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let leases = (try? encoder.encode(engine.leases)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let state = """
            state: \(engine.state)
            wantsLid: \(engine.wantsLid)
            power: \(engine.power)
            thermal: \(engine.thermal.rawValue) (0 nominal, 1 fair, 2 serious, 3 critical)
            lidClosed: \(engine.lidClosed.map(String.init(describing:)) ?? "unknown")
            """
        let sleep = sleepDisabled.map { $0 ? "1" : "0" } ?? "unknown"
        return [
            "leases.json": leases,
            "state.txt": state,
            "helper.txt": "Status: \(helperStatus)\nSleepDisabled: \(sleep)\n",
            "assertions.txt": assertions(),
            "mooring.log": logs()
        ]
    }

    static func write(_ files: [String: String], zipTo url: URL) throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "mooring-diagnostics-\(UUID().uuidString)/Mooring-diagnostics")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        for (name, contents) in files {
            try Data(contents.utf8).write(to: folder.appending(path: name))
        }
        try? FileManager.default.removeItem(at: url)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", folder.path, url.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "ditto failed"])
        }
    }

    /// The last day of Mooring's own log messages. Slow; call off the main actor.
    static func recentLogs() -> String {
        let log = Process()
        log.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        log.arguments = ["show", "--last", "1d", "--style", "compact", "--predicate", "subsystem == \"dev.mooring\""]
        let pipe = Pipe()
        log.standardOutput = pipe
        guard (try? log.run()) != nil else { return "log show failed to start" }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        log.waitUntilExit()
        return String(data: output, encoding: .utf8) ?? ""
    }

    private static func assertions() -> String {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let all = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return "unavailable" }
        let mine = all[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] ?? []
        let lines = mine.map { "\($0[kIOPMAssertionTypeKey] ?? "?") named \($0[kIOPMAssertionNameKey] ?? "?")" }
        return lines.isEmpty ? "none" : lines.joined(separator: "\n")
    }
}

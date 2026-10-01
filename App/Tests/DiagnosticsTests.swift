import AwakeKit
import Foundation
import Testing
@testable import Mooring

@MainActor
struct DiagnosticsTests {
    @Test func zipContainsEveryFile() throws {
        let zip = FileManager.default.temporaryDirectory.appending(path: "mooring-diag-\(UUID().uuidString).zip")
        try Diagnostics.write(["a.txt": "x", "b.txt": "y"], zipTo: zip)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-l", zip.path]
        let pipe = Pipe()
        unzip.standardOutput = pipe
        try unzip.run()
        unzip.waitUntilExit()
        let listing = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(listing.contains("a.txt"))
        #expect(listing.contains("b.txt"))
    }

    @Test func collectNamesTheFiles() {
        let engine = AwakeEngine(assertions: NullAssertions(), store: MemoryStore(), processes: NoProcesses(),
                                 lid: LidController(helper: FakeLidHelper()), settings: { AwakeSettings() })
        let files = Diagnostics.collect(engine: engine, helperStatus: .enabled, sleepDisabled: false, logs: { "log" })
        #expect(files.keys.sorted() == ["assertions.txt", "helper.txt", "leases.json", "mooring.log", "state.txt"])
        #expect(files["helper.txt"]?.contains("SleepDisabled: 0") == true)
    }
}

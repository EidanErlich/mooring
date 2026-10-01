import Foundation
import Testing
@testable import MooringCLICore

// Same table as Packages/AwakeKit/Tests/AwakeKitTests/DurationTableTests.swift; keep them identical.
private let sharedTable: [(TimeInterval, String)] = [
    (0, "0m"), (1, "1m"), (59, "1m"), (60, "1m"), (61, "2m"), (3599, "1h"), (3600, "1h"), (3601, "1h 1m"),
    (4320, "1h 12m"), (7200, "2h"), (-30, "0m")
]

@Test(arguments: sharedTable)
func cliTextMatchesTheSharedTable(seconds: TimeInterval, expected: String) {
    #expect(CLIText.remaining(seconds) == expected)
}

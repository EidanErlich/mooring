import AwakeKit
import Foundation
import Testing

// Same table as Packages/MooringIPC/Tests/MooringCLICoreTests/DurationTableTests.swift; keep them identical.
private let sharedTable: [(TimeInterval, String)] = [
    (0, "0m"), (1, "1m"), (59, "1m"), (60, "1m"), (61, "2m"), (3599, "1h"), (3600, "1h"), (3601, "1h 1m"),
    (4320, "1h 12m"), (7200, "2h"), (-30, "0m")
]

@Test(arguments: sharedTable)
func durationTextMatchesTheSharedTable(seconds: TimeInterval, expected: String) {
    #expect(DurationText.remaining(seconds) == expected)
}

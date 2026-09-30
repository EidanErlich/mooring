import Foundation
import Testing

private let captured = """
System-wide power settings:
 SleepDisabled\t\t0
Currently in use:
 standby              1
 sleep                1 (sleep prevented by Claude, powerd)
"""

struct PMSetTests {
    @Test func readsZeroFromRealOutput() {
        #expect(PMSet.sleepDisabled(inOutput: captured) == false)
    }

    @Test func readsOne() {
        let output = captured.replacingOccurrences(of: "SleepDisabled\t\t0", with: "SleepDisabled\t\t1")
        #expect(PMSet.sleepDisabled(inOutput: output) == true)
    }

    @Test func toleratesSpacesInsteadOfTabs() {
        #expect(PMSet.sleepDisabled(inOutput: " SleepDisabled    1\n") == true)
    }

    @Test func missingLineIsNil() {
        #expect(PMSet.sleepDisabled(inOutput: "Currently in use:\n sleep 1\n") == nil)
    }

    @Test func nonBinaryValueIsNil() {
        #expect(PMSet.sleepDisabled(inOutput: " SleepDisabled\t\t2\n") == nil)
        #expect(PMSet.sleepDisabled(inOutput: " SleepDisabled\t\tabc\n") == nil)
    }

    @Test func disableArgumentsAreFixed() {
        #expect(PMSet.disableSleepArguments(true) == ["-a", "disablesleep", "1"])
        #expect(PMSet.disableSleepArguments(false) == ["-a", "disablesleep", "0"])
        #expect(PMSet.readArguments == ["-g"])
    }
}

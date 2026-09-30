import AwakeKit
import Foundation
import IOKit.pwr_mgt
import Testing

/// The types of this process's assertions named "Mooring", sorted, read back from IOKit.
private func mooringAssertionTypes() -> [String] {
    var byProcess: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
          let all = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
    else { return [] }
    return (all[NSNumber(value: getpid())] ?? [])
        .filter { $0[kIOPMAssertionNameKey] as? String == IOPMAssertions.assertionName }
        .compactMap { $0[kIOPMAssertionTypeKey] as? String }
        .sorted()
}

@MainActor
@Suite(.serialized)
struct AssertionsTests {
    @Test func systemOnlyCreatesOneSystemAssertion() {
        let assertions = IOPMAssertions()
        assertions.apply(system: true, display: false)
        #expect(mooringAssertionTypes() == ["PreventUserIdleSystemSleep"])
        assertions.apply(system: false, display: false)
        #expect(mooringAssertionTypes() == [])
    }

    @Test func displayAddsDisplayAssertion() {
        let assertions = IOPMAssertions()
        assertions.apply(system: true, display: true)
        #expect(mooringAssertionTypes() == ["PreventUserIdleDisplaySleep", "PreventUserIdleSystemSleep"])
        assertions.apply(system: false, display: false)
        #expect(mooringAssertionTypes() == [])
    }

    @Test func applyIsIdempotent() {
        let assertions = IOPMAssertions()
        for _ in 0..<3 { assertions.apply(system: true, display: false) }
        #expect(mooringAssertionTypes() == ["PreventUserIdleSystemSleep"])
        assertions.apply(system: false, display: false)
    }
}

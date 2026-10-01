import AwakeKit
import Foundation
import Testing

/// The dropdown keeps one menu session: either a duration (the `menu` lease) or one
/// or more picked apps (`app-<pid>` leases), never both.
@MainActor
struct MenuSessionTests {
    private func harness(apps: [Int32] = [42, 43]) -> EngineHarness {
        let harness = EngineHarness()
        for pid in apps { harness.processes.startTimes[pid] = harness.clock }
        return harness
    }

    @Test func pickingAnAppReplacesTheTimerAndKeepsItsLevel() {
        let harness = harness()
        harness.engine.turnOnMenu(duration: 1800)
        harness.engine.setKeepScreenOn(true)
        harness.engine.anchor(whileAppRuns: 42, appName: "Xcode")
        #expect(harness.engine.leases.map(\.id) == ["app-42"])
        #expect(harness.engine.leases.first?.level == .screenOn)
    }

    @Test func severalAppsCanBePicked() {
        let harness = harness()
        harness.engine.anchor(whileAppRuns: 42, appName: "Xcode")
        harness.engine.anchor(whileAppRuns: 43, appName: "Safari")
        #expect(harness.engine.sessionApps.map(\.id) == ["app-42", "app-43"])
        #expect(harness.engine.menuLease == nil)
        #expect(harness.engine.hasMenuSession)
    }

    @Test func pickingADurationClearsEveryApp() {
        let harness = harness()
        harness.engine.anchor(whileAppRuns: 42, appName: "Xcode")
        harness.engine.anchor(whileAppRuns: 43, appName: "Safari")
        harness.engine.setAllowLidClose(true)
        harness.engine.turnOnMenu(duration: 3600)
        #expect(harness.engine.leases.map(\.id) == ["menu"])
        #expect(harness.engine.menuLease?.level.lid == true)
    }

    @Test func sessionTogglesApplyToEveryApp() {
        let harness = harness()
        harness.engine.anchor(whileAppRuns: 42, appName: "Xcode")
        harness.engine.anchor(whileAppRuns: 43, appName: "Safari")
        harness.engine.setKeepScreenOn(true)
        #expect(harness.engine.menuLease == nil)
        #expect(harness.engine.sessionApps.allSatisfy { $0.level.display })
        #expect(harness.engine.sessionLevel?.display == true)
    }

    @Test func turningOffEndsTheWholeSession() {
        let harness = harness()
        harness.engine.anchor(whileAppRuns: 42, appName: "Xcode")
        harness.engine.anchor(whileAppRuns: 43, appName: "Safari")
        harness.engine.toggleMenu()
        #expect(harness.engine.leases.isEmpty)
        #expect(!harness.engine.hasMenuSession)
    }

    @Test func sessionEndsWhenTheLastAppQuits() {
        let harness = harness()
        harness.engine.anchor(whileAppRuns: 42, appName: "Xcode")
        harness.engine.anchor(whileAppRuns: 43, appName: "Safari")
        harness.processes.exit(42)
        #expect(harness.engine.hasMenuSession)
        harness.processes.exit(43)
        #expect(!harness.engine.hasMenuSession)
    }
}

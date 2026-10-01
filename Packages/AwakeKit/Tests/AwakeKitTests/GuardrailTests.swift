import AwakeKit
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_000_000)
private let lidLease = Lease(id: "menu", owner: .menu, reason: "r", level: AwakeLevel(display: false, lid: true),
                             expiresAt: nil, createdAt: now)
private let systemLease = Lease(id: "menu", owner: .menu, reason: "r", level: .system, expiresAt: nil, createdAt: now)

private func power(_ percent: Int?, onAC: Bool) -> PowerSnapshot {
    PowerSnapshot(onAC: onAC, batteryPercent: percent)
}

private func optedIn() -> AwakeSettings {
    var settings = AwakeSettings()
    settings.allowLidOnBattery = true
    return settings
}

private func run(
    leases: [Lease] = [lidLease], _ power: PowerSnapshot, thermal: ProcessInfo.ThermalState = .nominal,
    lidClosed: Bool? = true, settings: AwakeSettings = AwakeSettings(), suspended: Set<Suspension> = []
) -> TargetState {
    target(leases: leases, power: power, thermal: thermal, lidClosed: lidClosed,
           settings: settings, now: now, suspended: suspended)
}

struct GuardrailTests {
    @Test func acHasNoSuspensions() {
        let state = run(power(80, onAC: true))
        #expect(state.lidSleepDisabled)
        #expect(state.suspensions.isEmpty)
    }

    @Test func lidNeedsACWithoutOptIn() {
        let state = run(power(80, onAC: false))
        #expect(state.suspensions == [.lidNeedsAC])
        #expect(!state.lidSleepDisabled)
        #expect(state.systemAssertion)
        #expect(run(power(80, onAC: false), settings: optedIn()).suspensions.isEmpty)
    }

    @Test func lowBatteryLidHasHysteresis() {
        let low = run(power(19, onAC: false), settings: optedIn())
        #expect(low.suspensions == [.lowBatteryLid])
        #expect(!low.lidSleepDisabled)
        let stillLow = run(power(30, onAC: false), settings: optedIn(), suspended: low.suspensions)
        #expect(stillLow.suspensions == [.lowBatteryLid])
        let charging = run(power(24, onAC: true), settings: optedIn(), suspended: stillLow.suspensions)
        #expect(charging.suspensions == [.lowBatteryLid])
        let resumed = run(power(25, onAC: true), settings: optedIn(), suspended: charging.suspensions)
        #expect(resumed.suspensions.isEmpty)
        #expect(resumed.lidSleepDisabled)
    }

    @Test func lowBatteryAllSuspendsEverything() {
        let state = run(power(9, onAC: false), settings: optedIn())
        #expect(state.suspensions.contains(.lowBatteryAll))
        #expect(!state.systemAssertion)
        #expect(!state.displayAssertion)
        #expect(!state.lidSleepDisabled)
        #expect(run(leases: [systemLease], power(9, onAC: false)).suspensions == [.lowBatteryAll])
        #expect(!run(leases: [systemLease], power(9, onAC: false)).systemAssertion)
    }

    @Test func lowBatteryAllResumesOnlyOnAC() {
        let onBattery = run(leases: [systemLease], power(50, onAC: false), suspended: [.lowBatteryAll])
        #expect(onBattery.suspensions == [.lowBatteryAll])
        #expect(run(leases: [systemLease], power(50, onAC: true), suspended: [.lowBatteryAll]).suspensions.isEmpty)
    }

    @Test func thermalSuspendsLidWhileClosedUntilNominal() {
        let hot = run(power(80, onAC: true), thermal: .serious)
        #expect(hot.suspensions == [.thermal])
        #expect(hot.systemAssertion)
        #expect(!hot.lidSleepDisabled)
        #expect(run(power(80, onAC: true), thermal: .fair, suspended: [.thermal]).suspensions == [.thermal])
        #expect(run(power(80, onAC: true), thermal: .nominal, suspended: [.thermal]).suspensions.isEmpty)
        #expect(run(power(80, onAC: true), thermal: .serious, lidClosed: false).suspensions.isEmpty)
        var noCutoff = AwakeSettings()
        noCutoff.thermalCutoff = false
        #expect(run(power(80, onAC: true), thermal: .critical, settings: noCutoff).suspensions.isEmpty)
    }

    @Test func thresholdsOffDisableTheirGuardrails() {
        var settings = optedIn()
        settings.lidBatteryThreshold = nil
        settings.allBatteryThreshold = nil
        #expect(run(power(3, onAC: false), settings: settings).suspensions.isEmpty)
    }

    @Test func noLidLeaseMeansNoLidSuspensions() {
        let state = run(leases: [systemLease], power(15, onAC: false), thermal: .critical)
        #expect(state.suspensions.isEmpty)
        #expect(state.systemAssertion)
    }

    @Test func desktopWithoutBatteryIsTreatedAsAC() {
        let state = run(PowerSnapshot(onAC: true, batteryPercent: nil))
        #expect(state.suspensions.isEmpty)
        #expect(state.lidSleepDisabled)
    }
}

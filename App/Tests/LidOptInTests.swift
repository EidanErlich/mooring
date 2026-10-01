import AwakeKit
import Testing
@testable import Mooring

struct LidOptInTests {
    @Test func needsConfirmationOnlyOnBatteryWithoutOptIn() {
        var settings = AwakeSettings()
        #expect(!LidOptIn.needsConfirmation(power: PowerSnapshot(onAC: true, batteryPercent: 80), settings: settings))
        #expect(LidOptIn.needsConfirmation(power: PowerSnapshot(onAC: false, batteryPercent: 80), settings: settings))
        #expect(!LidOptIn.needsConfirmation(power: PowerSnapshot(onAC: true, batteryPercent: nil), settings: settings))
        settings.allowLidOnBattery = true
        #expect(!LidOptIn.needsConfirmation(power: PowerSnapshot(onAC: false, batteryPercent: 80), settings: settings))
    }
}

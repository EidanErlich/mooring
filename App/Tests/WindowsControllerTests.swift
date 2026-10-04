import AwakeKit
import Defaults
import Foundation
import Testing
import WindowKit
@testable import Mooring

@MainActor
final class FakeTrust: AccessibilityTrust {
    var trusted: Bool
    var calls = 0
    var panesOpened = 0

    init(trusted: Bool) {
        self.trusted = trusted
    }

    func isTrusted() -> Bool {
        calls += 1
        return trusted
    }

    func openSettingsPane() {
        panesOpened += 1
    }
}

@MainActor
final class FakeRuntime: WindowsRuntime {
    var starts = 0
    var stops = 0
    private(set) var isRunning = false

    func start() {
        starts += 1
        isRunning = true
    }

    func stop() {
        stops += 1
        isRunning = false
    }
}

@MainActor
final class FakeSettings: WindowsSettings {
    var windowsEnabled: Bool

    init(enabled: Bool) {
        windowsEnabled = enabled
    }
}

/// A clock the test moves by hand; `advance` fires the scheduled tick at each interval it passes.
@MainActor
final class FakeClock: WindowsClock {
    private(set) var now = Date(timeIntervalSince1970: 0)
    private(set) var interval: TimeInterval?
    private var nextFire: Date?
    private var tick: (@MainActor @Sendable () -> Void)?

    func schedule(every interval: TimeInterval, _ tick: @escaping @MainActor @Sendable () -> Void) {
        self.interval = interval
        self.tick = tick
        nextFire = now.addingTimeInterval(interval)
    }

    func cancel() {
        interval = nil
        nextFire = nil
        tick = nil
    }

    func advance(_ seconds: TimeInterval) {
        let end = now.addingTimeInterval(seconds)
        while let interval, let next = nextFire, next <= end {
            now = next
            nextFire = next.addingTimeInterval(interval)
            tick?()
        }
        now = end
    }
}

@MainActor
private final class FakeSheet: AccessibilitySheetPresenting {
    var shown = 0
    var closed = 0

    func show() { shown += 1 }
    func close() { closed += 1 }
}

@MainActor
private struct Harness {
    let trust: FakeTrust
    let settings: FakeSettings
    let clock = FakeClock()
    let sheet = FakeSheet()
    let controller: WindowsController
    private let made: Box

    final class Box {
        var runtimes: [FakeRuntime] = []
    }

    init(enabled: Bool, trusted: Bool) {
        let trust = FakeTrust(trusted: trusted), settings = FakeSettings(enabled: enabled), made = Box()
        self.trust = trust
        self.settings = settings
        self.made = made
        controller = WindowsController(trust: trust, makeRuntime: {
            let runtime = FakeRuntime()
            made.runtimes.append(runtime)
            return runtime
        }, settings: settings, clock: clock)
        controller.sheet = sheet
    }

    var runtimes: [FakeRuntime] { made.runtimes }
    var running: Bool { made.runtimes.last?.isRunning == true }
}

extension WindowKitGlobalStateTests {
    /// Serialized with the Settings tests that build Loop's pages, which create Loop's singletons.
    @Suite
    @MainActor
    struct WindowsControllerOffTests {
        /// The real singleton counter catches any of Loop's managers created by launching.
        @Test func offMeansOff() {
            let before = WindowKit.instantiatedSingletons
            let harness = Harness(enabled: false, trusted: true)
            harness.controller.launch()
            harness.clock.advance(600)
            #expect(harness.trust.calls == 0)
            #expect(harness.runtimes.isEmpty)
            #expect(WindowKit.instantiatedSingletons == before)
            #expect(harness.clock.interval == nil)
            #expect(harness.controller.state == .off)
        }
    }
}

@MainActor
struct WindowsControllerTests {
    @Test func launchEnabledAndTrustedStarts() {
        let harness = Harness(enabled: true, trusted: true)
        harness.controller.launch()
        #expect(harness.controller.state == .on)
        #expect(harness.runtimes.count == 1)
        #expect(harness.running)
        #expect(harness.sheet.shown == 0)
    }

    @Test func launchEnabledUntrustedNeedsAccessibility() {
        let harness = Harness(enabled: true, trusted: false)
        harness.controller.launch()
        #expect(harness.controller.state == .needsAccessibility)
        #expect(harness.runtimes.isEmpty)
        #expect(harness.settings.windowsEnabled)
        #expect(harness.sheet.shown == 0)
    }

    @Test func turnOnTrustedStarts() {
        let harness = Harness(enabled: false, trusted: true)
        harness.controller.turnOn()
        #expect(harness.controller.state == .on)
        #expect(harness.settings.windowsEnabled)
        #expect(harness.running)
        #expect(harness.sheet.shown == 0)
        #expect(harness.clock.interval == 5)
    }

    @Test func turnOnUntrustedWaitsThenStarts() {
        let harness = Harness(enabled: false, trusted: false)
        harness.controller.turnOn()
        #expect(harness.controller.state == .waitingForTrust)
        #expect(harness.sheet.shown == 1)
        #expect(harness.clock.interval == 2)
        #expect(harness.runtimes.isEmpty)
        #expect(!harness.settings.windowsEnabled)

        harness.clock.advance(2)
        harness.clock.advance(2)
        #expect(harness.controller.state == .waitingForTrust)
        let pollsSoFar = harness.trust.calls
        harness.trust.trusted = true
        harness.clock.advance(2)
        #expect(harness.trust.calls == pollsSoFar + 1)
        #expect(harness.controller.state == .on)
        #expect(harness.running)
        #expect(harness.settings.windowsEnabled)
        #expect(harness.sheet.closed == 1)
        #expect(harness.clock.interval == 5)
    }

    @Test func turnOnTimesOutAfterFiveMinutes() {
        let harness = Harness(enabled: false, trusted: false)
        harness.controller.turnOn()
        harness.clock.advance(298)
        #expect(harness.controller.state == .waitingForTrust)
        harness.clock.advance(2)
        #expect(harness.controller.state == .off)
        #expect(!harness.settings.windowsEnabled)
        #expect(harness.runtimes.isEmpty)
        #expect(harness.sheet.closed == 1)
        #expect(harness.clock.interval == nil)
        let polls = harness.trust.calls
        harness.clock.advance(60)
        #expect(harness.trust.calls == polls)
    }

    @Test func cancelStopsPollingAndKeepsTheSetting() {
        let harness = Harness(enabled: false, trusted: false)
        harness.controller.turnOn()
        harness.controller.openSettingsPane()
        #expect(harness.trust.panesOpened == 1)
        harness.controller.cancelTurnOn()
        #expect(harness.controller.state == .off)
        #expect(!harness.settings.windowsEnabled)
        #expect(harness.sheet.closed == 1)
        #expect(harness.clock.interval == nil)
        harness.trust.trusted = true
        harness.clock.advance(60)
        #expect(harness.controller.state == .off)
        #expect(harness.runtimes.isEmpty)
    }

    @Test func revokedWhileOnStopsAndFlags() {
        let harness = Harness(enabled: true, trusted: true)
        harness.controller.launch()
        harness.trust.trusted = false
        harness.clock.advance(4)
        #expect(harness.controller.state == .on)
        harness.clock.advance(1)
        #expect(harness.controller.state == .needsAccessibility)
        #expect(harness.runtimes.first?.stops == 1)
        #expect(!harness.running)
        #expect(harness.settings.windowsEnabled)
        #expect(harness.clock.interval == 5)
        #expect(harness.sheet.shown == 0)
    }

    @Test func restoredResumes() {
        let harness = Harness(enabled: true, trusted: false)
        harness.controller.launch()
        harness.clock.advance(10)
        #expect(harness.controller.state == .needsAccessibility)
        harness.trust.trusted = true
        harness.clock.advance(5)
        #expect(harness.controller.state == .on)
        #expect(harness.running)
        #expect(harness.settings.windowsEnabled)
    }

    @Test func turnOffStopsAndClears() {
        let harness = Harness(enabled: true, trusted: true)
        harness.controller.launch()
        harness.controller.turnOff()
        #expect(harness.controller.state == .off)
        #expect(!harness.settings.windowsEnabled)
        #expect(harness.runtimes.first?.stops == 1)
        #expect(!harness.running)
        #expect(harness.clock.interval == nil)
        let polls = harness.trust.calls
        harness.clock.advance(60)
        #expect(harness.trust.calls == polls)
    }

    /// Starting again after off builds a fresh runtime: turning off releases the old one.
    @Test func turnOnAfterOffMakesAFreshRuntime() {
        let harness = Harness(enabled: false, trusted: true)
        harness.controller.turnOn()
        harness.controller.turnOff()
        harness.controller.turnOn()
        #expect(harness.runtimes.count == 2)
        #expect(harness.runtimes[0].starts == 1)
        #expect(harness.runtimes[1].starts == 1)
        #expect(harness.running)
    }

    /// Turning off while Accessibility is missing gives the menu-bar icon back to the awake state.
    @Test func turnOffFromNeedsAccessibilityClearsPill() {
        let harness = Harness(enabled: true, trusted: false)
        harness.controller.launch()
        func pill() -> MenuBarState {
            MenuBarState.from(leases: [], state: .off, wantsLid: false, helperEnabled: true,
                              windowsNeedAccessibility: harness.controller.wantsAttention, showTimeLeft: true, now: Date())
        }
        #expect(pill() == .attention(.windowsNeedAccessibility))

        harness.controller.turnOff()
        #expect(harness.controller.state == .off)
        #expect(!harness.settings.windowsEnabled)
        #expect(pill() == .off)
        #expect(harness.clock.interval == nil)

        harness.controller.launch()
        #expect(harness.controller.state == .off)
        #expect(pill() == .off)
    }

    @Test func windowsAreOffByDefault() {
        #expect(Defaults.Keys.windowsEnabled.defaultValue == false)
    }
}

import Defaults
import Foundation
import Observation
import WindowKit

/// What `WindowsController` starts and stops: WindowKit in the app, a fake in tests.
@MainActor
protocol WindowsRuntime: AnyObject {
    func start()
    func stop()
    var isRunning: Bool { get }
}

/// Where `windowsEnabled` lives.
@MainActor
protocol WindowsSettings: AnyObject {
    var windowsEnabled: Bool { get set }
}

/// The time source and repeating tick behind trust polling.
@MainActor
protocol WindowsClock: AnyObject {
    var now: Date { get }
    /// Calls `tick` every `interval` seconds until `cancel()`, replacing any earlier schedule.
    func schedule(every interval: TimeInterval, _ tick: @escaping @MainActor @Sendable () -> Void)
    func cancel()
}

/// The "needs Accessibility" sheet.
@MainActor
protocol AccessibilitySheetPresenting: AnyObject {
    func show()
    func close()
}

/// Owns Windows' lifecycle (docs/design/2026-10-03-stage-3a-windowkit-design.md, "Off means off").
/// While off, nothing in WindowKit is created and Accessibility is never asked about.
@MainActor @Observable
final class WindowsController {
    enum State: Equatable {
        case off
        /// Turn On was chosen without Accessibility; polling until it's granted or 5 minutes pass.
        case waitingForTrust
        case on // swiftlint:disable:this identifier_name
        /// Wanted on, but Accessibility is missing; resumes by itself when it returns.
        case needsAccessibility
    }

    static let trustPollInterval: TimeInterval = 2
    static let trustPollLimit: TimeInterval = 5 * 60
    static let revocationCheckInterval: TimeInterval = 5

    private(set) var state = State.off

    /// The menu-bar icon flags Windows only while it's wanted and Accessibility is missing.
    var wantsAttention: Bool { state == .needsAccessibility }

    /// Shown while waiting for trust after Turn On.
    @ObservationIgnored var sheet: (any AccessibilitySheetPresenting)?

    @ObservationIgnored private let trust: any AccessibilityTrust
    @ObservationIgnored private let makeRuntime: () -> any WindowsRuntime
    @ObservationIgnored private let settings: any WindowsSettings
    @ObservationIgnored private let clock: any WindowsClock
    @ObservationIgnored private var runtime: (any WindowsRuntime)?
    @ObservationIgnored private var trustDeadline: Date?

    /// `makeRuntime` runs only when Windows starts, so nothing in WindowKit exists while off.
    init(trust: any AccessibilityTrust, makeRuntime: @escaping () -> any WindowsRuntime,
         settings: any WindowsSettings, clock: any WindowsClock) {
        self.trust = trust
        self.makeRuntime = makeRuntime
        self.settings = settings
        self.clock = clock
    }

    /// At app launch. Never asks for Accessibility; with Windows off it doesn't even check.
    func launch() {
        guard settings.windowsEnabled else { return }
        if trust.isTrusted() {
            start()
        } else {
            enter(.needsAccessibility)
        }
    }

    /// Turn On…: starts now if trusted, otherwise asks macOS to list Mooring under Accessibility, shows
    /// the sheet and waits up to 5 minutes for trust.
    func turnOn() {
        switch state {
        case .on:
            return
        case .waitingForTrust:
            sheet?.show()
            return
        case .off, .needsAccessibility:
            break
        }
        if trust.isTrusted() {
            settings.windowsEnabled = true
            start()
        } else {
            trust.requestListing()
            trustDeadline = clock.now.addingTimeInterval(Self.trustPollLimit)
            enter(.waitingForTrust)
            sheet?.show()
        }
    }

    func turnOff() {
        stopRuntime()
        settings.windowsEnabled = false
        sheet?.close()
        enter(.off)
    }

    /// The sheet's Cancel: stops waiting and leaves `windowsEnabled` as it was.
    func cancelTurnOn() {
        guard state == .waitingForTrust else { return }
        stopWaiting()
    }

    /// The sheet's "Open Privacy & Security".
    func openSettingsPane() {
        trust.openSettingsPane()
    }

    /// Driven by the clock: polls trust while waiting, and checks for revocation or return otherwise.
    func tick() {
        switch state {
        case .off:
            clock.cancel()
        case .waitingForTrust:
            if trust.isTrusted() {
                settings.windowsEnabled = true
                sheet?.close()
                start()
            } else if let trustDeadline, clock.now >= trustDeadline {
                stopWaiting()
            }
        case .on:
            if !trust.isTrusted() {
                stopRuntime()
                enter(.needsAccessibility)
            }
        case .needsAccessibility:
            if trust.isTrusted() {
                start()
            }
        }
    }

    // MARK: - Private

    private func start() {
        let runtime = runtime ?? makeRuntime()
        self.runtime = runtime
        runtime.start()
        enter(.on)
    }

    /// Stops and releases WindowKit, so turning on again starts from nothing.
    private func stopRuntime() {
        runtime?.stop()
        runtime = nil
    }

    /// Ends a Turn On that never got trust: back to off, or to needing Accessibility if it was wanted already.
    private func stopWaiting() {
        sheet?.close()
        enter(settings.windowsEnabled ? .needsAccessibility : .off)
    }

    private func enter(_ newState: State) {
        state = newState
        if newState != .waitingForTrust {
            trustDeadline = nil
        }
        switch newState {
        case .off:
            clock.cancel()
        case .waitingForTrust:
            clock.schedule(every: Self.trustPollInterval) { [weak self] in self?.tick() }
        case .on, .needsAccessibility:
            clock.schedule(every: Self.revocationCheckInterval) { [weak self] in self?.tick() }
        }
    }
}

/// `windowsEnabled` in Mooring's own defaults.
@MainActor
final class DefaultsWindowsSettings: WindowsSettings {
    var windowsEnabled: Bool {
        get { Defaults[.windowsEnabled] }
        set { Defaults[.windowsEnabled] = newValue }
    }
}

/// A main-run-loop timer; it exists only while Windows is waiting, on or needs Accessibility.
@MainActor
final class TimerWindowsClock: WindowsClock {
    private var timer: Timer?

    var now: Date { Date() }

    func schedule(every interval: TimeInterval, _ tick: @escaping @MainActor @Sendable () -> Void) {
        cancel()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

extension WindowKit: WindowsRuntime {}

extension WindowsController {
    /// The app's controller. WindowKit is constructed only inside `makeRuntime`, when Windows starts.
    static func live() -> WindowsController {
        let controller = WindowsController(
            trust: LiveAccessibilityTrust(), makeRuntime: { WindowKit() },
            settings: DefaultsWindowsSettings(), clock: TimerWindowsClock()
        )
        controller.sheet = AccessibilitySheetWindow(controller: controller)
        return controller
    }
}

import ClipKit
import Defaults
import Foundation
import Observation

/// What `ClipboardController` starts and stops: ClipKit in the app, a fake in tests.
@MainActor
protocol ClipKitRuntime: AnyObject {
    func start()
    func stop()
    var isRunning: Bool { get }
    func clear(all: Bool)
}

/// `clipboardEnabled` and ClipKit's "Clear history on quit".
@MainActor
protocol ClipboardSettings: AnyObject {
    var clipboardEnabled: Bool { get set }
    var clearHistoryOnQuit: Bool { get }
}

/// Owns Clipboard's lifecycle. While off, ClipKit is never created: no Maccy singleton, no store,
/// no polling and no hotkey.
@MainActor @Observable
final class ClipboardController {
    private(set) var isOn = false

    @ObservationIgnored private let settings: any ClipboardSettings
    @ObservationIgnored private let storeURL: URL
    @ObservationIgnored private let makeKit: (URL) -> any ClipKitRuntime
    @ObservationIgnored private var kit: (any ClipKitRuntime)?

    /// `makeKit` runs only when Clipboard starts, and is given where the history is kept.
    init(settings: any ClipboardSettings, storeURL: URL = ClipKit.defaultStoreURL,
         makeKit: @escaping (URL) -> any ClipKitRuntime) {
        self.settings = settings
        self.storeURL = storeURL
        self.makeKit = makeKit
    }

    /// At app launch: starts only if Clipboard was left on.
    func launch() {
        guard settings.clipboardEnabled else { return }
        start()
    }

    func turnOn() {
        settings.clipboardEnabled = true
        start()
    }

    /// Stops polling and unregisters the hotkey. Saved history stays on disk.
    func turnOff() {
        kit?.stop()
        kit = nil
        isOn = false
        settings.clipboardEnabled = false
    }

    /// At quit: with "Clear history on quit" on, drops every unpinned item.
    func willTerminate() {
        guard let kit, kit.isRunning, settings.clearHistoryOnQuit else { return }
        kit.clear(all: false)
    }

    private func start() {
        guard !isOn else { return }
        let kit = self.kit ?? makeKit(storeURL)
        self.kit = kit
        kit.start()
        isOn = true
    }
}

/// `clipboardEnabled` in Mooring's own defaults; "Clear history on quit" in ClipKit's.
@MainActor
final class DefaultsClipboardSettings: ClipboardSettings {
    var clipboardEnabled: Bool {
        get { Defaults[.clipboardEnabled] }
        set { Defaults[.clipboardEnabled] = newValue }
    }

    var clearHistoryOnQuit: Bool {
        ClipKit.settingsValues().clearOnQuit
    }
}

extension ClipKit: ClipKitRuntime {}

extension ClipboardController {
    /// The app's controller. ClipKit is constructed only inside `makeKit`, when Clipboard starts.
    static func live() -> ClipboardController {
        ClipboardController(settings: DefaultsClipboardSettings()) { ClipKit(storeURL: $0) }
    }
}

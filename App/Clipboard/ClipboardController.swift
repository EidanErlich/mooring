import AppKit
import ClipKit
import Defaults
import Foundation
import Observation

/// What `ClipboardController` starts, stops and reads: ClipKit in the app, a fake in tests.
@MainActor
protocol ClipKitRuntime: AnyObject {
    func start()
    func stop()
    var isRunning: Bool { get }
    func clear(all: Bool)
    func recentEntries(limit: Int) -> [ClipboardEntry]
    func copyEntry(_ id: AnyHashable)
    var isPaused: Bool { get set }
    func ignoreNextCopy()
    func openPopup()
}

/// One copy in the history, as the dropdown lists it.
struct ClipboardEntry {
    let id: AnyHashable
    let title: String
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

    // MARK: The history. While off none of these reaches ClipKit.

    /// The newest items; none while off, or until the history has loaded after turning on.
    func recent(limit: Int) -> [ClipboardEntry] {
        guard isOn, let kit else { return [] }
        return kit.recentEntries(limit: limit)
    }

    /// Puts the item back on the clipboard.
    func copy(_ id: AnyHashable) {
        guard isOn else { return }
        kit?.copyEntry(id)
    }

    /// Whether recording is paused; false while off.
    var isPaused: Bool {
        guard isOn, let kit else { return false }
        return kit.isPaused
    }

    func setPaused(_ paused: Bool) {
        guard isOn else { return }
        kit?.isPaused = paused
    }

    func ignoreNextCopy() {
        guard isOn else { return }
        kit?.ignoreNextCopy()
    }

    /// Clears unpinned items, or every item with `all`.
    func clear(all: Bool) {
        guard isOn else { return }
        kit?.clear(all: all)
    }

    /// Opens the ⇧⌘C popup.
    func showPopup() {
        guard isOn else { return }
        kit?.openPopup()
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

extension ClipKit: ClipKitRuntime {
    func recentEntries(limit: Int) -> [ClipboardEntry] {
        recent(limit: limit).map { ClipboardEntry(id: $0.id, title: $0.title) }
    }

    func copyEntry(_ id: AnyHashable) {
        guard let id = id.base as? ClipItem.ID else { return }
        copy(id)
    }
}

extension ClipboardController {
    /// The app's controller. ClipKit is constructed only inside `makeKit`, when Clipboard starts, and
    /// builds the popup (`ClipboardPanel`) only once it runs.
    static func live(statusBarButton: @escaping @MainActor () -> NSStatusBarButton?,
                     openSettings: @escaping @MainActor () -> Void) -> ClipboardController {
        ClipboardController(settings: DefaultsClipboardSettings()) { url in
            let kit = ClipKit(storeURL: url)
            kit.openSettings = openSettings
            kit.makePopupPanel = { ClipboardPanel(kit: $0, statusBarButton: statusBarButton()) }
            return kit
        }
    }
}

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
    /// Clears after `confirm` says yes, unless the user asked not to be asked (ClipKit's rule).
    func confirmAndClear(all: Bool, confirm: @MainActor () -> ClearConfirmation)
    /// The newest unpinned items, at most `limit`.
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
    var isPinned = false
    /// An image, which has no title.
    var isImage = false
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
    @ObservationIgnored private let confirmClear: @MainActor () -> ClearConfirmation
    @ObservationIgnored private var kit: (any ClipKitRuntime)?
    /// Bumped whenever the history folder may have appeared or gone, so `hasSavedHistory` is re-read.
    private var storeChanges = 0

    /// `makeKit` runs only when Clipboard starts, and is given where the history is kept.
    /// `confirmClear` asks before clearing (Maccy's alert; tests answer for it).
    init(settings: any ClipboardSettings, storeURL: URL = ClipKit.defaultStoreURL,
         confirmClear: @escaping @MainActor () -> ClearConfirmation = { ClipKit.askToClear() },
         makeKit: @escaping (URL) -> any ClipKitRuntime) {
        self.settings = settings
        self.storeURL = storeURL
        self.confirmClear = confirmClear
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

    /// Stops polling and unregisters the hotkey. Saved history stays on disk, except that with "Clear
    /// history on quit" set the unpinned items are cleared first, as quitting would.
    func turnOff() {
        if let kit, kit.isRunning, settings.clearHistoryOnQuit {
            kit.clear(all: false)
        }
        kit?.stop()
        kit = nil
        isOn = false
        settings.clipboardEnabled = false
        storeChanges += 1
    }

    /// Whether history is saved on disk (its folder exists). Checked without starting ClipKit.
    var hasSavedHistory: Bool {
        _ = storeChanges
        return FileManager.default.fileExists(atPath: storeURL.deletingLastPathComponent().path(percentEncoded: false))
    }

    /// While off: removes the history folder and everything in it, pins included. It never starts
    /// ClipKit; history a run earlier in this session loaded is dropped too.
    func deleteHistory() {
        guard !isOn else { return }
        ClipKit.discardLoadedHistory()
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
        storeChanges += 1
    }

    /// At quit: with "Clear history on quit" on, drops every unpinned item.
    func willTerminate() {
        guard let kit, kit.isRunning, settings.clearHistoryOnQuit else { return }
        kit.clear(all: false)
    }

    // MARK: The history. While off none of these reaches ClipKit.

    /// The newest unpinned items (pins stay in the popup); none while off, or until the history has
    /// loaded after turning on.
    func recent(limit: Int) -> [ClipboardEntry] {
        guard isOn, let kit else { return [] }
        return Array(kit.recentEntries(limit: limit).filter { !$0.isPinned }.prefix(limit))
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

    /// Clears unpinned items, or every item with `all`, once the user confirms (unless they asked
    /// not to be asked). It may show an alert, so it never runs while a menu is tracking.
    func confirmAndClear(all: Bool) {
        guard isOn else { return }
        kit?.confirmAndClear(all: all, confirm: confirmClear)
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
        storeChanges += 1
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
        recent(limit: limit, includingPinned: false).map {
            ClipboardEntry(id: $0.id, title: $0.title, isPinned: $0.isPinned, isImage: $0.isImage)
        }
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

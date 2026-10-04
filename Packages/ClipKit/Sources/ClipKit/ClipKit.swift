import AppKit
import Defaults
@_exported import KeyboardShortcuts
import os
import SwiftData
import SwiftUI

/// Mooring's handle on the vendored Maccy clipboard history. Nothing in Maccy runs, and no store
/// exists, until `start()`.
@MainActor
public final class ClipKit {
    /// `~/Library/Application Support/Mooring/Clipboard/Storage.sqlite`.
    public nonisolated static let defaultStoreURL = URL.applicationSupportDirectory
        .appending(path: "Mooring/Clipboard/Storage.sqlite")

    /// The popup hotkey (⇧⌘C by default). It's registered only while a ClipKit runs.
    public nonisolated static let popupShortcutName: KeyboardShortcuts.Name = .popup

    /// The popup hotkey as menus show it ("⇧⌘C"), or nil when it has none.
    public static var popupShortcutDescription: String? {
        KeyboardShortcuts.getShortcut(for: popupShortcutName)?.description
    }

    /// The instance whose `start()` is in effect. Maccy's singletons are process-wide, so only one runs.
    /// Weak, so a released instance neither keeps running nor blocks a later start.
    private(set) static weak var runningOwner: ClipKit?

    /// Whether any ClipKit has started in this process, so Maccy's state exists.
    private(set) static var hasStarted = false

    /// Builds the popup window on each `start()`, once Maccy's state exists. Without it the popup
    /// hotkey does nothing.
    public var makePopupPanel: (@MainActor (ClipKit) -> any PopupPanel)?

    /// The popup's "Preferences…" and ⌘, call this.
    public var openSettings: (@MainActor () -> Void)?

    private let storeURL: URL?
    private let inMemory: Bool
    private let environment: ClipboardEnvironment
    private var checkIntervalObserver: Task<Void, Never>?
    /// Whether this instance started and hasn't stopped; `deinit` can't use the zeroed weak owner.
    private var ownsRunning = false

    public var isRunning: Bool {
        Self.runningOwner === self
    }

    /// Whether the popup hotkey is registered, which is only while running.
    public var isPopupShortcutRegistered: Bool {
        isRunning && ClipKitShortcuts.registered.contains(.popup)
    }

    /// Creates nothing and reads nothing. `storeURL` nil means `defaultStoreURL`, except under a test
    /// host, where it means in memory.
    public convenience init(storeURL: URL? = nil, inMemory: Bool = false) {
        self.init(storeURL: storeURL, inMemory: inMemory, environment: .default)
    }

    init(storeURL: URL?, inMemory: Bool, environment: ClipboardEnvironment) {
        self.storeURL = storeURL
        self.inMemory = inMemory
        self.environment = environment
    }

    /// Releasing a running instance stops everything it started.
    deinit {
        checkIntervalObserver?.cancel()
        guard ownsRunning else { return }
        let tearDown = {
            MainActor.assumeIsolated {
                // Another instance may have started meanwhile; then it owns Maccy's singletons.
                if ClipKit.runningOwner == nil {
                    ClipKit.tearDown()
                }
            }
        }
        if Thread.isMainThread {
            tearDown()
        } else {
            DispatchQueue.main.async(execute: tearDown)
        }
    }

    /// Opens the store, starts polling the clipboard and registers the popup hotkey.
    /// Calling it again while running does nothing.
    public func start() {
        guard Self.runningOwner == nil else { return }
        Self.runningOwner = self
        Self.hasStarted = true
        ownsRunning = true

        Self.setStoreLocation(prepareStoreLocation())
        let clipboard = Clipboard.shared
        clipboard.environment = environment
        clipboard.onNewCopy { History.shared.add($0) }
        clipboard.start()
        checkIntervalObserver = Task {
            for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
                Clipboard.shared.restart()
            }
        }

        ClipKitShortcuts.popupActive = true
        AppState.shared.popup.start()
        AppState.shared.panel = makePopupPanel?(self)
        ModifierFlags.setMonitoring(true)
        Task { try? await History.shared.load() }
    }

    /// Stops polling at once and unregisters the hotkey. The store stays open but untouched.
    /// Calling it again, or before `start()`, does nothing.
    public func stop() {
        guard isRunning else { return }
        Self.runningOwner = nil
        ownsRunning = false

        checkIntervalObserver?.cancel()
        checkIntervalObserver = nil
        Self.tearDown()
    }

    private static func tearDown() {
        Clipboard.shared.stop()
        ClipKitShortcuts.popupActive = false
        AppState.shared.popup.stop()  // closes the panel
        AppState.shared.panel = nil
        ModifierFlags.setMonitoring(false)
    }

    /// Sets where the store opens, unless it already opened this process: it stays there, so a later
    /// start (say, after an earlier one fell back to memory) doesn't try to move it.
    static func setStoreLocation(_ location: Storage.Location) {
        guard !Storage.isOpen else { return }
        Storage.location = location
    }

    private func prepareStoreLocation() -> Storage.Location {
        if inMemory { return .memory }
        guard let url = storeURL ?? (TestHost.isActive ? nil : Self.defaultStoreURL) else { return .memory }
        let location = Self.storeLocation(for: url, fileManager: .default)
        // Under a test host the store is always in memory; the folder is still created and secured.
        return TestHost.isActive ? .memory : location
    }

    /// The store on disk if its folder could be created and secured; otherwise in memory, so history
    /// is never written to a folder others can read or that's backed up.
    static func storeLocation(for storeURL: URL, fileManager: FileManager) -> Storage.Location {
        do {
            try prepareStoreFolder(for: storeURL, fileManager: fileManager)
            return .file(storeURL)
        } catch {
            let code = (error as NSError).code
            ClipKitLog.logger.error("Couldn't secure the clipboard store folder (error \(code)); keeping history in memory")
            return .memory
        }
    }

    /// Creates the store's folder owner-only (`0700`), tightens it if it already existed, and keeps it
    /// out of backups.
    static func prepareStoreFolder(for storeURL: URL, fileManager: FileManager) throws {
        var folder = storeURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path(percentEncoded: false))
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }
}

// MARK: - Data surface

/// The answer to "Are you sure you want to clear the history?".
public struct ClearConfirmation: Equatable, Sendable {
    public var confirmed: Bool
    /// The alert's "don't ask again" checkbox was ticked.
    public var dontAskAgain: Bool

    public init(confirmed: Bool, dontAskAgain: Bool = false) {
        self.confirmed = confirmed
        self.dontAskAgain = dontAskAgain
    }
}

/// One recorded copy, as the app's menus show it.
public struct ClipItem: Identifiable, Hashable, Sendable {
    public let id: PersistentIdentifier
    public let title: String
    /// The name of the app the copy came from, when known.
    public let app: String?
    public let isPinned: Bool
    /// An image copy, which has no title.
    public let isImage: Bool
}

extension ClipKit {
    /// The newest items, pinned ones placed as the popup places them, or without pinned ones when
    /// `includingPinned` is false. Empty while not running.
    public func recent(limit: Int, includingPinned: Bool = true) -> [ClipItem] {
        guard isRunning else { return [] }
        let items = includingPinned ? History.shared.all : History.shared.all.filter(\.isUnpinned)
        return items.prefix(max(limit, 0)).map { decorator in
            ClipItem(
                id: decorator.item.persistentModelID,
                title: decorator.title,
                app: decorator.application,
                isPinned: decorator.isPinned,
                isImage: decorator.hasImage
            )
        }
    }

    /// Puts the item back on the clipboard.
    public func copy(_ id: ClipItem.ID) {
        guard let item = item(id) else { return }
        Clipboard.shared.copy(item)
    }

    /// Copies the item, then pastes it with ⌘V if Mooring has Accessibility. Without it, it only
    /// copies; it never asks for Accessibility.
    public func paste(_ id: ClipItem.ID, plain: Bool) {
        guard let item = item(id) else { return }
        Clipboard.shared.copy(item, removeFormatting: plain)
        Clipboard.shared.paste()
    }

    /// While paused, copies aren't recorded.
    public var isPaused: Bool {
        get { Defaults[.ignoreEvents] && !Defaults[.ignoreOnlyNextEvent] }
        set {
            Defaults[.ignoreOnlyNextEvent] = false
            Defaults[.ignoreEvents] = newValue
        }
    }

    /// Skips recording the next copy only.
    public func ignoreNextCopy() {
        guard !isPaused else { return }
        Defaults[.ignoreEvents] = true
        Defaults[.ignoreOnlyNextEvent] = true
    }

    /// Clears unpinned items, or every item with `all`. Does nothing while not running.
    public func clear(all: Bool) {
        guard isRunning else { return }
        if all {
            History.shared.clearAll()
        } else {
            History.shared.clear()
        }
    }

    /// Drops the history a ClipKit loaded earlier in this process, pins included, so deleting the
    /// store's folder doesn't leave it in memory to come back on the next start. Does nothing while
    /// one runs, or if none ever started (it creates nothing).
    public static func discardLoadedHistory() {
        guard hasStarted, runningOwner == nil else { return }
        History.shared.clearAll()
    }

    /// Opens the popup where the popup-position setting says, unless it's open. Does nothing while
    /// not running.
    public func openPopup() {
        guard isRunning else { return }
        let popup = AppState.shared.popup
        guard popup.isClosed() else { return }
        popup.open(height: popup.height)
    }

    /// Clears as the popup's Clear and Clear All do: after asking "Are you sure you want to clear the
    /// history?", unless the user ticked "don't ask again" before. `confirm` shows the question;
    /// tests replace it. Does nothing while not running.
    public func confirmAndClear(all: Bool, confirm: @MainActor () -> ClearConfirmation = ClipKit.askToClear) {
        guard isRunning else { return }
        var suppressed = Defaults[.suppressClearAlert]
        guard Self.shouldClear(alertSuppressed: &suppressed, confirm: confirm) else { return }
        if suppressed != Defaults[.suppressClearAlert] {
            Defaults[.suppressClearAlert] = suppressed
        }
        clear(all: all)
    }

    /// The rule behind `confirmAndClear`: clear without asking while the question is suppressed;
    /// otherwise ask, and on a yes with "don't ask again" ticked, suppress it from now on.
    public static func shouldClear(alertSuppressed: inout Bool, confirm: () -> ClearConfirmation) -> Bool {
        if alertSuppressed { return true }
        let answer = confirm()
        guard answer.confirmed else { return false }
        if answer.dontAskAgain { alertSuppressed = true }
        return true
    }

    /// Asks with Maccy's clear alert, which has a "don't ask again" checkbox. Runs modally.
    public static func askToClear() -> ClearConfirmation {
        let alert = makeClearAlert()
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        return ClearConfirmation(
            confirmed: response == .alertFirstButtonReturn,
            dontAskAgain: alert.suppressionButton?.state == .on
        )
    }

    static func makeClearAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("clear_alert_message", bundle: .module, comment: "")
        alert.informativeText = NSLocalizedString("clear_alert_comment", bundle: .module, comment: "")
        alert.addButton(withTitle: NSLocalizedString("clear_alert_confirm", bundle: .module, comment: ""))
        alert.addButton(withTitle: NSLocalizedString("clear_alert_cancel", bundle: .module, comment: ""))
        alert.buttons.first?.hasDestructiveAction = true
        alert.showsSuppressionButton = true
        return alert
    }

    /// Maccy's popup content, or an empty view while not running: building it creates Maccy's
    /// singletons and opens the store.
    public func popupView() -> AnyView {
        guard isRunning else { return AnyView(EmptyView()) }
        return AnyView(ContentView())
    }

    private func item(_ id: ClipItem.ID) -> HistoryItem? {
        guard isRunning else { return nil }
        return History.shared.all.first { $0.item.persistentModelID == id }?.item
    }
}

// MARK: - Singleton tracking

extension ClipKit {
    private nonisolated static let singletonCount = OSAllocatedUnfairLock(initialState: 0)

    /// Debug counter: how many of Maccy's `shared` singletons this process has created.
    public nonisolated static var instantiatedSingletons: Int {
        singletonCount.withLock { $0 }
    }

    /// Wraps each of Maccy's `static let shared = …` initialisers, so creating one is counted.
    nonisolated static func track<Instance: AnyObject>(_ instance: Instance) -> Instance {
        singletonCount.withLock { $0 += 1 }
        return instance
    }
}

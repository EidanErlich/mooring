import AppKit
import Defaults
import KeyboardShortcuts
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

    /// The instance whose `start()` is in effect. Maccy's singletons are process-wide, so only one runs.
    private(set) static var runningOwner: ObjectIdentifier?

    private let storeURL: URL?
    private let inMemory: Bool
    private let environment: ClipboardEnvironment
    private var checkIntervalObserver: Task<Void, Never>?

    public var isRunning: Bool {
        Self.runningOwner == ObjectIdentifier(self)
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

    /// Opens the store, starts polling the clipboard and registers the popup hotkey.
    /// Calling it again while running does nothing.
    public func start() {
        guard Self.runningOwner == nil else { return }
        Self.runningOwner = ObjectIdentifier(self)

        Storage.location = prepareStoreLocation()
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
        Task { try? await History.shared.load() }
    }

    /// Stops polling at once and unregisters the hotkey. The store stays open but untouched.
    /// Calling it again, or before `start()`, does nothing.
    public func stop() {
        guard isRunning else { return }
        Self.runningOwner = nil

        checkIntervalObserver?.cancel()
        checkIntervalObserver = nil
        Clipboard.shared.stop()
        ClipKitShortcuts.popupActive = false
        AppState.shared.popup.stop()
    }

    private func prepareStoreLocation() -> Storage.Location {
        if inMemory { return .memory }
        guard let url = storeURL ?? (TestHost.isActive ? nil : Self.defaultStoreURL) else { return .memory }
        do {
            try Self.prepareStoreFolder(for: url)
        } catch {
            ClipKitLog.logger.error("Could not prepare the clipboard store folder: \(error.localizedDescription)")
        }
        return .file(url)
    }

    /// Creates the store's folder owner-only (`0700`), tightens it if it already existed, and keeps it
    /// out of backups.
    static func prepareStoreFolder(for storeURL: URL) throws {
        var folder = storeURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path(percentEncoded: false))
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }
}

// MARK: - Data surface

/// One recorded copy, as the app's menus show it.
public struct ClipItem: Identifiable, Hashable, Sendable {
    public let id: PersistentIdentifier
    public let title: String
    /// The name of the app the copy came from, when known.
    public let app: String?
    public let isPinned: Bool
}

extension ClipKit {
    /// The newest items, pinned ones placed as the popup places them. Empty while not running.
    public func recent(limit: Int) -> [ClipItem] {
        guard isRunning else { return [] }
        return History.shared.all.prefix(max(limit, 0)).map { decorator in
            ClipItem(
                id: decorator.item.persistentModelID,
                title: decorator.title,
                app: decorator.application,
                isPinned: decorator.isPinned
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

    /// Maccy's popup content. Build it only while running: it reads the history.
    public func popupView() -> AnyView {
        AnyView(ContentView())
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

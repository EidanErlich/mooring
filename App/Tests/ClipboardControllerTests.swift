import ClipKit
import Foundation
import Testing
@testable import Mooring

@MainActor
final class FakeClipKit: ClipKitRuntime {
    var starts = 0
    var stops = 0
    var clears: [Bool] = []
    private(set) var isRunning = false

    func start() {
        starts += 1
        isRunning = true
    }

    func stop() {
        stops += 1
        isRunning = false
    }

    func clear(all: Bool) {
        touches += 1
        clears.append(all)
    }

    // The history surface. `touches` counts every call to it.
    var touches = 0
    var entries: [ClipboardEntry] = []
    var recentLimits: [Int] = []
    var copies: [AnyHashable] = []
    var ignoreNextCopies = 0
    var popupOpens = 0
    private var paused = false

    func recentEntries(limit: Int) -> [ClipboardEntry] {
        touches += 1
        recentLimits.append(limit)
        return Array(entries.prefix(limit))
    }

    func copyEntry(_ id: AnyHashable) {
        touches += 1
        copies.append(id)
    }

    var isPaused: Bool {
        get {
            touches += 1
            return paused
        }
        set {
            touches += 1
            paused = newValue
        }
    }

    func ignoreNextCopy() {
        touches += 1
        ignoreNextCopies += 1
    }

    func openPopup() {
        touches += 1
        popupOpens += 1
    }
}

@MainActor
final class FakeClipboardSettings: ClipboardSettings {
    var clipboardEnabled: Bool
    var clearHistoryOnQuit: Bool

    init(enabled: Bool, clearOnQuit: Bool = false) {
        clipboardEnabled = enabled
        clearHistoryOnQuit = clearOnQuit
    }
}

@MainActor
private final class ClipboardHarness {
    let settings: FakeClipboardSettings
    let storeURL: URL
    private(set) var kits: [FakeClipKit] = []
    private(set) var storeURLsRequested: [URL] = []
    private(set) var controller: ClipboardController!

    var kit: FakeClipKit? { kits.last }

    init(enabled: Bool, clearOnQuit: Bool = false) {
        settings = FakeClipboardSettings(enabled: enabled, clearOnQuit: clearOnQuit)
        storeURL = FileManager.default.temporaryDirectory
            .appending(path: "mooring-clipboard-tests-\(UUID().uuidString)/Clipboard/Storage.sqlite")
        controller = ClipboardController(settings: settings, storeURL: storeURL) { [unowned self] url in
            storeURLsRequested.append(url)
            let kit = FakeClipKit()
            kits.append(kit)
            return kit
        }
    }

    var storeFolderExists: Bool {
        FileManager.default.fileExists(atPath: storeURL.deletingLastPathComponent().path(percentEncoded: false))
    }
}

/// Serialized with the other suites that read a process-wide singleton count.
@Suite(.serialized)
@MainActor
struct ClipKitGlobalStateTests {}

extension ClipKitGlobalStateTests {
    @Suite
    @MainActor
    struct ClipboardControllerOffTests {
        /// The real counter catches any of Maccy's singletons created while Clipboard is off.
        @Test func offMeansNoStoreNoPolling() {
            let before = ClipKit.instantiatedSingletons
            let harness = ClipboardHarness(enabled: false)
            harness.controller.launch()
            harness.controller.willTerminate()
            #expect(harness.kits.isEmpty)
            #expect(!harness.controller.isOn)
            #expect(!harness.storeFolderExists)
            #expect(ClipKit.instantiatedSingletons == before)
        }
    }
}

@MainActor
struct ClipboardControllerTests {
    @Test func launchEnabledStarts() {
        let harness = ClipboardHarness(enabled: true)
        harness.controller.launch()
        #expect(harness.controller.isOn)
        #expect(harness.kits.count == 1)
        #expect(harness.kit?.isRunning == true)
        #expect(harness.settings.clipboardEnabled)
    }

    @Test func turnOnCreatesStoreAndStarts() {
        let harness = ClipboardHarness(enabled: false)
        harness.controller.turnOn()
        #expect(harness.controller.isOn)
        #expect(harness.settings.clipboardEnabled)
        #expect(harness.storeURLsRequested == [harness.storeURL])
        #expect(harness.kit?.starts == 1)
        harness.controller.turnOn()
        #expect(harness.kits.count == 1)
        #expect(harness.kit?.starts == 1)
    }

    @Test func turnOffStops() {
        let harness = ClipboardHarness(enabled: false)
        harness.controller.turnOn()
        harness.controller.turnOff()
        #expect(!harness.controller.isOn)
        #expect(!harness.settings.clipboardEnabled)
        #expect(harness.kit?.stops == 1)
        #expect(harness.kit?.isRunning == false)
        harness.controller.turnOn()
        #expect(harness.kits.count == 2)
        #expect(harness.kit?.isRunning == true)
    }

    /// Stopping is what unregisters the popup hotkey and ends polling; ClipKit's own tests cover that.
    @Test func turnOffUnregistersHotkey() {
        let harness = ClipboardHarness(enabled: true)
        harness.controller.launch()
        let kit = harness.kit
        harness.controller.turnOff()
        #expect(kit?.stops == 1)
        #expect(kit?.isRunning == false)
        harness.controller.turnOff()
        #expect(kit?.stops == 1)
    }

    @Test func clearOnQuitClears() {
        let harness = ClipboardHarness(enabled: true, clearOnQuit: true)
        harness.controller.launch()
        harness.controller.willTerminate()
        #expect(harness.kit?.clears == [false])
    }

    @Test func quitKeepsHistoryUnlessAsked() {
        let harness = ClipboardHarness(enabled: true, clearOnQuit: false)
        harness.controller.launch()
        harness.controller.willTerminate()
        #expect(harness.kit?.clears == [])

        let stopped = ClipboardHarness(enabled: false, clearOnQuit: true)
        stopped.controller.turnOn()
        stopped.controller.turnOff()
        stopped.controller.willTerminate()
        #expect(stopped.kit?.clears == [])
    }
}

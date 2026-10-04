import AppKit
import Defaults
import Foundation
import KeyboardShortcuts
import Logging
import Testing
@testable import ClipKit

extension ClipKitGlobalStateTests {
    @Suite
    @MainActor
    struct IsolationTests {
        @Test func defaultsUseOwnSuite() throws {
            Fixture.resetSettings()
            defer { Fixture.resetSettings() }

            #expect(UserDefaults.clipKitProductionSuiteName == "dev.mooring.clipboard")
            #expect(UserDefaults.clipKitSuiteName == "dev.mooring.clipboard.tests")
            #expect(Defaults.Keys.size.suite === UserDefaults.clipKit)
            #expect(Defaults.Keys.ignoredApps.suite === UserDefaults.clipKit)

            Defaults[.size] = 123
            let suite = try #require(UserDefaults(suiteName: "dev.mooring.clipboard.tests"))
            #expect(suite.integer(forKey: "historySize") == 123)
            #expect(UserDefaults.standard.integer(forKey: "historySize") != 123)
        }

        @Test func noSingletonsBeforeStart() async {
            await #expect(processExitsWith: .success) {
                let (before, after) = await MainActor.run {
                    let kit = ClipKit(storeURL: nil, inMemory: true)
                    _ = kit.isRunning
                    _ = kit.isPaused
                    _ = kit.recent(limit: 10)
                    kit.clear(all: true)
                    _ = ClipKit.settingsValues()
                    _ = ClipKit.popupShortcutName
                    _ = kit.popupView()
                    ClipKit.discardLoadedHistory()
                    let before = ClipKit.instantiatedSingletons
                    KeyboardShortcutsFixture.parkPopupShortcut()
                    kit.start()
                    let after = ClipKit.instantiatedSingletons
                    kit.stop()
                    return (before, after)
                }
                exit(before == 0 && after > 0 ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test func popupHotkeyOnlyWhileRunning() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            #expect(!kit.isPopupShortcutRegistered)

            Fixture.start(kit)
            #expect(kit.isPopupShortcutRegistered)
            #expect(AppState.shared.popup.isStarted)

            kit.stop()
            #expect(!kit.isPopupShortcutRegistered)
            #expect(!AppState.shared.popup.isStarted)

            // Closing the panel re-enables the hotkey in Maccy; while stopped it must not.
            AppState.shared.popup.reset()
            ClipKitShortcuts.enable(.popup)
            #expect(!ClipKitShortcuts.registered.contains(.popup))
        }

        @Test func popupViewIsEmptyWhileOff() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            let monitorsBefore = ModifierFlags.monitoringCount
            _ = kit.popupView()
            #expect(ModifierFlags.monitoringCount == monitorsBefore)
        }

        /// The popup view's modifier-flags monitor runs only while ClipKit runs, and goes with the view.
        @Test func modifierFlagsMonitorOnlyWhileRunning() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            let idle = ModifierFlags()
            #expect(!idle.isMonitoring)

            Fixture.start(kit)
            var flags: ModifierFlags? = ModifierFlags()
            #expect(flags?.isMonitoring == true)
            #expect(idle.isMonitoring)

            kit.stop()
            #expect(flags?.isMonitoring == false)
            #expect(!idle.isMonitoring)

            Fixture.start(kit)
            #expect(flags?.isMonitoring == true)
            weak var released = flags
            flags = nil
            #expect(released == nil)
            #expect(ModifierFlags.monitoringCount == 1) // only `idle`
            kit.stop()
            #expect(ModifierFlags.monitoringCount == 0)
        }

        /// Opening the store records where it opened; asking for another place afterwards is a bug.
        @Test func storeLocationChangeAfterOpenTraps() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    Storage.location = .memory
                    _ = Storage.shared
                    Storage.location = .file(URL(filePath: "/tmp/dev.mooring.clipkit.tests.never/Storage.sqlite"))
                }
            }
        }

        @Test func releasedKitStopsEverything() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            var kit: ClipKit? = Fixture.kit(pasteboard: scratch)
            Fixture.start(kit!)
            #expect(Clipboard.shared.pollingTimer != nil)
            weak var released = kit
            kit = nil
            #expect(released == nil)
            #expect(Clipboard.shared.pollingTimer == nil)
            #expect(!AppState.shared.popup.isStarted)
            #expect(!ClipKitShortcuts.registered.contains(.popup))

            let next = Fixture.kit(pasteboard: scratch)
            next.start()
            #expect(next.isRunning)
            next.stop()
        }

        /// Pin, delete and preview are never registered, but unregistering one must not take down the
        /// popup hotkey when the user gave it the same keys.
        @Test func unusedShortcutSharingThePopupKeysKeepsThePopup() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            Fixture.start(kit)
            defer {
                kit.stop()
                ClipKitShortcuts.unregister = { KeyboardShortcuts.disable($0) }
                Fixture.resetSettings()
            }
            let pinKeys = KeyboardShortcuts.getShortcut(for: .pin) // creates .pin before the swap
            var unregistered: [KeyboardShortcuts.Name] = []
            ClipKitShortcuts.unregister = { unregistered.append($0) }

            KeyboardShortcuts.setShortcut(pinKeys, for: .popup)
            ClipKitShortcuts.disable(.pin)
            #expect(!unregistered.contains(.pin))
            #expect(kit.isPopupShortcutRegistered)

            KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.f18, modifiers: [.command, .option]), for: .popup)
            ClipKitShortcuts.disable(.pin)
            #expect(unregistered.contains(.pin))
        }

        @Test func logsOnlyWarningsUnderTests() {
            #expect(ClipKitLog.logger.logLevel == .warning)
        }

        /// Maccy's `print` calls wrote app paths and errors to stdout; everything goes through ClipKitLog.
        @Test func noPrintsInVendoredSources() throws {
            let sources = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .appending(path: "../../Sources/ClipKit")
                .standardizedFileURL
            var offenders: [String] = []
            let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            for case let file as URL in files where file.pathExtension == "swift" {
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
                for (index, line) in lines.enumerated()
                where ["print(", "NSLog(", "debugPrint("].contains(where: line.contains) {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
            #expect(offenders.isEmpty, "Direct output: \(offenders)")
        }

        @Test func popupInitRegistersNothing() {
            let popup = Popup()
            #expect(!popup.isStarted)
            #expect(!popup.hasEventsMonitor)
        }

        @Test func stringsResolveFromModuleBundle() {
            #expect(NSLocalizedString("search_placeholder", bundle: .clipKit, comment: "") == "type to search…")
            #expect(NSLocalizedString("clear_all", bundle: .clipKit, comment: "") == "Clear all")
            #expect(PopupPosition.cursor.description == "Cursor")
            #expect(PinsPosition.top.description == "Top")
            #expect(SearchVisibility.always.description == "Always")
            #expect(Sorter.By.lastCopiedAt.description == "Time of last copy")
        }

        /// Every localized lookup in the vendored sources names ClipKit's bundle; without it SwiftUI
        /// and Foundation look in the app's main bundle and show raw keys such as `search_placeholder`.
        @Test func everyLocalizedLookupNamesTheModuleBundle() throws {
            let sources = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .appending(path: "../../Sources/ClipKit/Maccy")
                .standardizedFileURL
            let lookups = ["NSLocalizedString(", "Text(\"", "LocalizedStringKey(", ".help(help", "confirmationDialog(",
                           "Text(confirmation", "Text(placeholder", "TextField(placeholder"]
            var offenders: [String] = []
            let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            for case let file as URL in files where file.pathExtension == "swift" {
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
                for (index, line) in lines.enumerated() where !line.contains("#Preview") {
                    guard lookups.contains(where: line.contains), !line.contains("Text(\"\\(") else { continue }
                    if !line.contains("bundle: .module") && !line.contains("verbatim:") {
                        offenders.append("\(file.lastPathComponent):\(index + 1)")
                    }
                }
            }
            #expect(offenders.isEmpty, "Localized lookups without bundle: .module: \(offenders)")
        }

        /// Maccy's code registers hotkeys only through `ClipKitShortcuts`, which refuses while stopped.
        @Test func hotkeysRegisterOnlyThroughTheGuard() throws {
            let sources = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .appending(path: "../../Sources/ClipKit/Maccy")
                .standardizedFileURL
            var offenders: [String] = []
            let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                for call in ["KeyboardShortcuts.enable(", "KeyboardShortcuts.disable(", "KeyboardShortcuts.onKeyUp("]
                where text.contains(call) {
                    offenders.append("\(file.lastPathComponent): \(call)")
                }
                let keyDowns = text.components(separatedBy: "KeyboardShortcuts.onKeyDown(").count - 1
                if keyDowns > 0 && (file.lastPathComponent != "Popup.swift" || keyDowns > 1) {
                    offenders.append("\(file.lastPathComponent): KeyboardShortcuts.onKeyDown(")
                }
            }
            #expect(offenders.isEmpty, "Hotkey registration outside ClipKitShortcuts: \(offenders)")
        }
    }
}

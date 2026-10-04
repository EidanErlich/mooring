import Foundation
import Testing
@testable import ClipKit

extension ClipKitGlobalStateTests {
    @Suite
    @MainActor
    struct StoreTests {
        @Test func defaultStoreIsUnderMooring() {
            #expect(ClipKit.defaultStoreURL.path(percentEncoded: false)
                .hasSuffix("/Library/Application Support/Mooring/Clipboard/Storage.sqlite"))
        }

        @Test func storeNotCreatedBeforeStart() throws {
            let home = Fixture.temporaryFolder()
            defer { try? FileManager.default.removeItem(at: home) }
            let storeURL = home.appending(path: "Mooring/Clipboard/Storage.sqlite")
            let scratch = TestPasteboard()
            defer { scratch.release() }

            let kit = ClipKit(storeURL: storeURL, inMemory: false, environment: Fixture.environment(scratch))
            _ = kit.isRunning
            _ = kit.recent(limit: 5)
            _ = ClipKit.settingsValues()
            kit.clear(all: true)
            #expect(!FileManager.default.fileExists(atPath: home.path(percentEncoded: false)))

            Fixture.resetSettings()
            kit.start()
            defer { kit.stop() }
            #expect(FileManager.default.fileExists(atPath: storeURL.deletingLastPathComponent().path(percentEncoded: false)))
        }

        @Test func storeFolderIs0700AndExcludedFromBackup() throws {
            let home = Fixture.temporaryFolder()
            defer { try? FileManager.default.removeItem(at: home) }
            let folder = home.appending(path: "Mooring/Clipboard", directoryHint: .isDirectory)
            // A folder left from before, too open, is tightened.
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755]
            )
            let scratch = TestPasteboard()
            defer { scratch.release() }

            let kit = ClipKit(
                storeURL: folder.appending(path: "Storage.sqlite"), inMemory: false, environment: Fixture.environment(scratch)
            )
            Fixture.resetSettings()
            kit.start()
            defer { kit.stop() }

            let attributes = try FileManager.default.attributesOfItem(atPath: folder.path(percentEncoded: false))
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
            var fresh = folder
            fresh.removeAllCachedResourceValues()
            #expect(try fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        }

        /// If the folder can't be created or secured, the store stays in memory rather than open unsecured.
        @Test func unsecurableFolderFallsBackToMemory() throws {
            let home = Fixture.temporaryFolder()
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path(percentEncoded: false))
                try? FileManager.default.removeItem(at: home)
            }

            let securable = home.appending(path: "ok/Clipboard/Storage.sqlite")
            #expect(ClipKit.storeLocation(for: securable, fileManager: .default) == .file(securable))

            let refusesChmod = home.appending(path: "chmod/Clipboard/Storage.sqlite")
            #expect(ClipKit.storeLocation(for: refusesChmod, fileManager: RefusingChmodFileManager()) == .memory)

            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: home.path(percentEncoded: false))
            let readOnly = home.appending(path: "readonly/Clipboard/Storage.sqlite")
            #expect(ClipKit.storeLocation(for: readOnly, fileManager: .default) == .memory)
        }

        @Test func inMemoryCreatesNoFolder() {
            let home = Fixture.temporaryFolder()
            defer { try? FileManager.default.removeItem(at: home) }
            let scratch = TestPasteboard()
            defer { scratch.release() }

            let kit = ClipKit(
                storeURL: home.appending(path: "Clipboard/Storage.sqlite"), inMemory: true, environment: Fixture.environment(scratch)
            )
            Fixture.start(kit)
            kit.stop()
            #expect(!FileManager.default.fileExists(atPath: home.path(percentEncoded: false)))
        }
    }
}

private final class RefusingChmodFileManager: FileManager {
    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

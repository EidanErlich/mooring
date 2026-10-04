import Foundation
import Testing
@testable import Mooring

struct CLIInstallerTests {
    private let fileManager = FileManager.default

    private struct Folder {
        let root: URL
        let link: URL
        let target: URL
    }

    /// A fresh temp folder plus the link and target paths inside it.
    private func makeFolder() throws -> Folder {
        let root = fileManager.temporaryDirectory.appendingPathComponent("mooring-installer-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("bundle-mooring")
        try Data("binary".utf8).write(to: target)
        return Folder(root: root, link: root.appendingPathComponent("home/.local/bin/mooring"), target: target)
    }

    @Test func missingWhenNoLink() throws {
        let folder = try makeFolder()
        let (root, link, target) = (folder.root, folder.link, folder.target)
        defer { try? fileManager.removeItem(at: root) }
        #expect(CLIInstaller.state(link: link, target: target) == .missing)
    }

    @Test func installCreatesFolderAndLink() throws {
        let folder = try makeFolder()
        let (root, link, target) = (folder.root, folder.link, folder.target)
        defer { try? fileManager.removeItem(at: root) }
        try CLIInstaller.install(link: link, target: target)
        #expect(try fileManager.destinationOfSymbolicLink(atPath: link.path) == target.path)
    }

    @Test func installedWhenLinkMatches() throws {
        let folder = try makeFolder()
        let (root, link, target) = (folder.root, folder.link, folder.target)
        defer { try? fileManager.removeItem(at: root) }
        try CLIInstaller.install(link: link, target: target)
        #expect(CLIInstaller.state(link: link, target: target) == .installed)
    }

    @Test func pointsElsewhereIsReported() throws {
        let folder = try makeFolder()
        let (root, link, target) = (folder.root, folder.link, folder.target)
        defer { try? fileManager.removeItem(at: root) }
        let other = root.appendingPathComponent("other-mooring")
        try CLIInstaller.install(link: link, target: other)
        #expect(CLIInstaller.state(link: link, target: target) == .pointsElsewhere(other.path))
    }

    @Test func reinstallReplacesAStaleLink() throws {
        let folder = try makeFolder()
        let (root, link, target) = (folder.root, folder.link, folder.target)
        defer { try? fileManager.removeItem(at: root) }
        try CLIInstaller.install(link: link, target: root.appendingPathComponent("other-mooring"))
        try CLIInstaller.install(link: link, target: target)
        #expect(CLIInstaller.state(link: link, target: target) == .installed)
    }

    @Test func neverReplacesARegularFile() throws {
        let folder = try makeFolder()
        let (root, link, target) = (folder.root, folder.link, folder.target)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: link)
        #expect(throws: CLIInstallerError.notALink) { try CLIInstaller.install(link: link, target: target) }
        #expect(try Data(contentsOf: link) == Data("mine".utf8))
        #expect(CLIInstaller.state(link: link, target: target) == .notALink)
    }

    @Test func directoryIsNotALinkAndIsNeverReplaced() throws {
        let folder = try makeFolder()
        let (root, link, target) = (folder.root, folder.link, folder.target)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: link, withIntermediateDirectories: true)
        #expect(CLIInstaller.state(link: link, target: target) == .notALink)
        #expect(throws: CLIInstallerError.notALink) { try CLIInstaller.install(link: link, target: target) }
        var isFolder: ObjCBool = false
        #expect(fileManager.fileExists(atPath: link.path, isDirectory: &isFolder) && isFolder.boolValue)
        #expect(CLIInstallerError.notALink.errorDescription
            == "Something that isn't a link is already at ~/.local/bin/mooring. Move it away first.")
    }

    @Test func regularFileIsNotALink() throws {
        let folder = try makeFolder()
        let (root, link, target) = (folder.root, folder.link, folder.target)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: link)
        #expect(CLIInstaller.state(link: link, target: target) == .notALink)
    }
}

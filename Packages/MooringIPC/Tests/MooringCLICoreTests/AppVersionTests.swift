import Foundation
import Testing
@testable import MooringCLICore

/// A temp folder holding `Mooring.app` at `version`, with the CLI at `Contents/Helpers/mooring`. Returns the folder
/// and the CLI's path.
private func makeBundle(version: String) throws -> (folder: URL, executable: URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mc-version-\(UUID().uuidString)")
    let contents = folder.appendingPathComponent("Mooring.app/Contents")
    try FileManager.default.createDirectory(at: contents.appendingPathComponent("Helpers"), withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleShortVersionString": version, "CFBundleIdentifier": "dev.mooring.app"], format: .xml, options: 0
    )
    try plist.write(to: contents.appendingPathComponent("Info.plist"))
    let executable = contents.appendingPathComponent("Helpers/mooring")
    try Data().write(to: executable)
    return (folder, executable)
}

@Test func versionReadsEnclosingBundle() throws {
    let bundle = try makeBundle(version: "1.2.3")
    defer { try? FileManager.default.removeItem(at: bundle.folder) }
    #expect(AppVersion.current(executable: bundle.executable.path) == "1.2.3")
}

@Test func versionFollowsSymlink() throws {
    // `~/.local/bin/mooring` is a link into the app; the version is the app's, not unknown.
    let bundle = try makeBundle(version: "4.5.6")
    defer { try? FileManager.default.removeItem(at: bundle.folder) }
    let bin = bundle.folder.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let link = bin.appendingPathComponent("mooring")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle.executable)
    #expect(AppVersion.current(executable: link.path) == "4.5.6")
}

@Test func versionUnknownOutsideBundle() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mc-version-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let loose = folder.appendingPathComponent("mooring")
    try Data().write(to: loose)
    #expect(AppVersion.current(executable: loose.path) == "unknown")
    #expect(AppVersion.current(executable: folder.appendingPathComponent("missing").path) == "unknown")
    // A bundle without a version is no better.
    let bare = folder.appendingPathComponent("Bare.app/Contents/Helpers")
    try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
    try Data().write(to: bare.appendingPathComponent("mooring"))
    #expect(AppVersion.current(executable: bare.appendingPathComponent("mooring").path) == "unknown")
}

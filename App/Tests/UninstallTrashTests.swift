import AppKit
import Foundation
import Testing
@testable import Mooring

private struct FakeTrashError: Error {}

/// Records the reveal, and answers whether the app is still in place.
@MainActor
private final class FakeTrash {
    var stillThere: Bool
    var recycleThrows: Bool
    private(set) var revealed: [URL] = []

    init(stillThere: Bool, recycleThrows: Bool) {
        self.stillThere = stillThere
        self.recycleThrows = recycleThrows
    }

    func move(_ app: URL) async throws {
        try await Uninstaller.moveToTrash(
            app,
            recycle: { _ in if self.recycleThrows { throw FakeTrashError() } },
            exists: { _ in self.stillThere },
            reveal: { self.revealed.append($0) }
        )
    }
}

@MainActor
struct UninstallTrashTests {
    private let app = URL(fileURLWithPath: "/Applications/Mooring.app")

    @Test func movedAppIsDone() async throws {
        let trash = FakeTrash(stillThere: false, recycleThrows: false)
        try await trash.move(app)
        #expect(trash.revealed.isEmpty)
    }

    /// macOS can move Mooring's own running bundle and still report an error: the app has left its place, so it's done.
    @Test func errorAfterTheAppLeftIsIgnored() async throws {
        let trash = FakeTrash(stillThere: false, recycleThrows: true)
        try await trash.move(app)
        #expect(trash.revealed.isEmpty)
    }

    @Test func appStillInPlaceIsShownInFinder() async {
        let trash = FakeTrash(stillThere: true, recycleThrows: true)
        await #expect(throws: (any Error).self) { try await trash.move(app) }
        #expect(trash.revealed == [app])
    }

    @Test func stillInPlaceMessageSaysWhatToDo() async {
        let trash = FakeTrash(stillThere: true, recycleThrows: true)
        do {
            try await trash.move(app)
            Issue.record("expected an error")
        } catch {
            #expect(error.localizedDescription == Uninstaller.dragToTrashMessage)
        }
    }
}

/// AppKit won't terminate while a sheet is attached ("App termination blocked by modal sheet"), and the uninstall
/// sheet is still up when the steps finish.
@MainActor
struct UninstallQuitTests {
    /// A real window, shown off-screen, with a sheet attached (AppKit attaches sheets only to visible windows).
    private func windowWithSheet() async throws -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 200, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled],
                             backing: .buffered, defer: false)
        window.beginSheet(sheet, completionHandler: nil)
        try await Task.sleep(for: .milliseconds(100))
        return window
    }

    @Test func endsSheetsBeforeTerminating() async throws {
        let window = try await windowWithSheet()
        defer { window.close() }
        #expect(window.attachedSheet != nil)
        var sheetsWhenTerminating: Int?
        Uninstaller.quitAfterUninstall(
            windows: [window],
            terminate: { sheetsWhenTerminating = window.attachedSheet == nil ? 0 : 1 },
            exit: {},
            fallback: .seconds(30)
        )
        try await Task.sleep(for: .milliseconds(200))
        #expect(window.attachedSheet == nil)
        #expect(sheetsWhenTerminating == 0)
    }

    @Test func exitsIfTerminationStillDoesNotHappen() async throws {
        var exited = false
        Uninstaller.quitAfterUninstall(windows: [], terminate: {}, exit: { exited = true }, fallback: .milliseconds(100))
        try await Task.sleep(for: .milliseconds(400))
        #expect(exited)
    }
}

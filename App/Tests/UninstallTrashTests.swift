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

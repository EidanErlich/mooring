import AppKit
import KeyboardShortcuts
import Testing
import XCTest
@testable import ClipKit

/// Notes a pasteboard's change count, so a test can tell whether anything wrote to it since.
/// Only the count is read, never the contents.
struct PasteboardGuard {
    let pasteboard: NSPasteboard
    let startCount: Int

    init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        startCount = pasteboard.changeCount
    }

    var endCount: Int { pasteboard.changeCount }
    var moved: Bool { endCount != startCount }
}

/// Fails any test, or any test in a suite, during which the real clipboard changed.
struct GeneralPasteboardUnchangedTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let guarded = PasteboardGuard()
        try await function()
        #expect(
            !guarded.moved,
            "NSPasteboard.general changed during \(test.name): \(guarded.startCount) → \(guarded.endCount)"
        )
    }
}

extension Trait where Self == GeneralPasteboardUnchangedTrait {
    static var generalPasteboardUnchanged: Self { Self() }
}

/// The XCTest counterpart, for Maccy's own test classes.
class GeneralPasteboardGuardedTestCase: XCTestCase {
    override func invokeTest() {
        let guarded = PasteboardGuard()
        super.invokeTest()
        XCTAssertEqual(
            guarded.endCount,
            guarded.startCount,
            "NSPasteboard.general changed during \(name)"
        )
    }
}

enum KeyboardShortcutsFixture {
    /// The popup hotkey for test processes: a combination no one presses. KeyboardShortcuts keeps it
    /// in the test runner's own defaults, never Mooring's.
    static func parkPopupShortcut() {
        let parked = KeyboardShortcuts.Shortcut(.f19, modifiers: [.command, .option, .control, .shift])
        if KeyboardShortcuts.getShortcut(for: .popup) != parked {
            KeyboardShortcuts.setShortcut(parked, for: .popup)
        }
    }
}

extension ClipKitGlobalStateTests {
    @Suite
    @MainActor
    struct PasteboardGuardTests {
        /// Proves the guard on a scratch pasteboard; proving it on the real one would mean writing to it.
        @Test func guardCatchesAWrite() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let guarded = PasteboardGuard(scratch.pasteboard)
            #expect(!guarded.moved)

            scratch.write(string: "fixture")
            #expect(guarded.moved)
        }
    }
}

import AppKit
import Defaults
import Testing
@testable import ClipKit

extension ClipKitGlobalStateTests {
    @Suite
    @MainActor
    struct ClearTests {
        /// A running kit with "one", "two" and "three" recorded, "two" pinned.
        private func recordedKit(_ scratch: TestPasteboard) -> ClipKit {
            let kit = Fixture.kit(pasteboard: scratch)
            Fixture.start(kit)
            for text in ["one", "two", "three"] {
                scratch.write(string: text)
                Fixture.poll()
            }
            History.shared.togglePin(History.shared.all.first { $0.item.title == "two" })
            return kit
        }

        /// After Clipboard is turned off its history can be deleted; what this process loaded goes with it.
        @Test func discardLoadedHistoryOnlyWhileStopped() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = recordedKit(scratch)
            defer { kit.stop(); Fixture.resetSettings() }

            ClipKit.discardLoadedHistory()
            #expect(Set(Fixture.recordedTitles()) == ["one", "two", "three"])

            kit.stop()
            let singletons = ClipKit.instantiatedSingletons
            ClipKit.discardLoadedHistory()
            #expect(Fixture.recordedTitles().isEmpty)  // pins too
            #expect(ClipKit.instantiatedSingletons == singletons)
        }

        @Test func clearAsksFirstAndCancelKeepsHistory() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = recordedKit(scratch)
            defer { kit.stop(); Fixture.resetSettings() }
            var asked = 0

            kit.confirmAndClear(all: false) {
                asked += 1
                return ClearConfirmation(confirmed: false, dontAskAgain: true)
            }
            #expect(asked == 1)
            #expect(Set(Fixture.recordedTitles()) == ["one", "two", "three"])
            #expect(!Defaults[.suppressClearAlert])  // ticking it then cancelling doesn't count

            kit.confirmAndClear(all: false) {
                asked += 1
                return ClearConfirmation(confirmed: true)
            }
            #expect(asked == 2)
            #expect(Fixture.recordedTitles() == ["two"])  // the pinned one stays
        }

        @Test func dontAskAgainSkipsTheQuestionFromThenOn() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = recordedKit(scratch)
            defer { kit.stop(); Fixture.resetSettings() }
            var asked = 0

            kit.confirmAndClear(all: false) {
                asked += 1
                return ClearConfirmation(confirmed: true, dontAskAgain: true)
            }
            #expect(Defaults[.suppressClearAlert])
            #expect(Fixture.recordedTitles() == ["two"])

            kit.confirmAndClear(all: true) {
                asked += 1
                return ClearConfirmation(confirmed: false)
            }
            #expect(asked == 1)
            #expect(Fixture.recordedTitles().isEmpty)
        }

        @Test func clearAlertUsesMaccysStringsAndSuppressionBox() {
            let alert = ClipKit.makeClearAlert()
            #expect(alert.messageText == "Are you sure you want to clear the history?")
            #expect(alert.informativeText == "You can't undo this action.")
            #expect(alert.buttons.map(\.title) == ["Clear", "Cancel"])
            #expect(alert.showsSuppressionButton)
        }

        @Test func recentCanLeaveOutPinnedItems() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = recordedKit(scratch)
            defer { kit.stop(); Fixture.resetSettings() }

            let unpinned = kit.recent(limit: 10, includingPinned: false)
            #expect(unpinned.map(\.title) == ["three", "one"])
            #expect(unpinned.allSatisfy { !$0.isPinned })
            #expect(kit.recent(limit: 10).first { $0.title == "two" }?.isPinned == true)
            #expect(kit.recent(limit: 1, includingPinned: false).map(\.title) == ["three"])
        }
    }
}

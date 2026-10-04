import Defaults
import Foundation
import SwiftData
import Testing
@testable import ClipKit

extension ClipKitGlobalStateTests {
    @Suite
    @MainActor
    struct LifecycleTests {
        @Test func startAndStopAreIdempotent() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            kit.stop()
            #expect(!kit.isRunning)

            Fixture.start(kit)
            let timer = Clipboard.shared.pollingTimer
            kit.start()
            #expect(kit.isRunning)
            #expect(Clipboard.shared.pollingTimer === timer)

            kit.stop()
            kit.stop()
            #expect(!kit.isRunning)
        }

        @Test func onlyOneKitRunsAtATime() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let first = Fixture.kit(pasteboard: scratch)
            let second = Fixture.kit(pasteboard: scratch)
            Fixture.start(first)
            second.start()
            #expect(first.isRunning)
            #expect(!second.isRunning)
            second.stop()
            #expect(first.isRunning)
            first.stop()
        }

        @Test func stopInvalidatesTimer() throws {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            Fixture.start(kit)
            let timer = try #require(Clipboard.shared.pollingTimer)
            #expect(timer.isValid)

            kit.stop()
            #expect(!timer.isValid)
            #expect(Clipboard.shared.pollingTimer == nil)

            // A changed check interval restarts polling only while running.
            Defaults[.clipboardCheckInterval] = 0.25
            Clipboard.shared.restart()
            #expect(Clipboard.shared.pollingTimer == nil)
            Fixture.resetSettings()
        }

        @Test func copyAfterStopNotRecorded() async throws {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            Fixture.start(kit)
            scratch.write(string: "while-on")
            Fixture.poll()
            #expect(Fixture.recordedTitles() == ["while-on"])

            kit.stop()
            let stored = try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>())
            scratch.write(string: "after-off")
            Fixture.poll() // as a timer tick already queued would
            try? await Task.sleep(for: .milliseconds(Int(Defaults[.clipboardCheckInterval] * 1000) + 200))
            #expect(Fixture.recordedTitles() == ["while-on"])
            #expect(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>()) == stored)
            #expect(kit.recent(limit: 10).isEmpty) // nothing is read while off
        }

        @Test func pauseAndIgnoreNextCopy() {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            Fixture.start(kit)
            defer { kit.stop() }

            kit.isPaused = true
            #expect(kit.isPaused)
            scratch.write(string: "while-paused")
            Fixture.poll()
            kit.isPaused = false
            #expect(!kit.isPaused)

            kit.ignoreNextCopy()
            scratch.write(string: "ignored-once")
            Fixture.poll()
            scratch.write(string: "recorded")
            Fixture.poll()
            #expect(Fixture.recordedTitles() == ["recorded"])
        }

        @Test func recentCopyAndClear() throws {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch, sourceApp: { "com.apple.TextEdit" })
            Fixture.start(kit)
            defer { kit.stop() }

            for text in ["one", "two", "three"] {
                scratch.write(string: text)
                Fixture.poll()
            }
            let recent = kit.recent(limit: 2)
            #expect(recent.map(\.title) == ["three", "two"])
            #expect(recent.allSatisfy { !$0.isPinned })

            let one = try #require(kit.recent(limit: 10).last)
            kit.copy(one.id)
            #expect(scratch.pasteboard.string(forType: .string) == "one")

            kit.clear(all: true)
            #expect(kit.recent(limit: 10).isEmpty)
        }
    }
}

import AppKit
import Defaults
import Foundation
import SwiftData
import Testing
@testable import ClipKit

extension ClipKitGlobalStateTests {
    @Suite
    @MainActor
    struct PerformanceTests {
        /// The wall-clock limits, with room for a shared CI runner (`CI=true`), which runs several times slower.
        static func budget(_ limit: Duration) -> Duration {
            ProcessInfo.processInfo.environment["CI"] == "true" ? limit * 5 : limit
        }

        /// A ~55 MB image copy is read and recorded on the main thread; it must not stall the menu for long.
        @Test func largeItemRecordsWithinBudget() throws {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            Fixture.start(kit)
            defer { kit.stop() }

            let side = 3_700
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            let tiff = try #require(bitmap.tiffRepresentation)
            #expect(tiff.count > 50_000_000)
            scratch.write([.tiff: tiff])

            let clock = ContinuousClock()
            let elapsed = clock.measure { Fixture.poll() }
            #expect(History.shared.all.count == 1)
            #expect(elapsed < Self.budget(.seconds(2)), "recording a \(tiff.count / 1_000_000) MB image took \(elapsed)")

            // A copy of many files has one pasteboard item per file. Up to the limit it's recorded...
            scratch.pasteboard.clearContents()
            scratch.pasteboard.writeObjects(fileURLs(Clipboard.maxRecordedContents))
            let atLimit = clock.measure { Fixture.poll() }
            #expect(History.shared.all.count == 2)
            #expect(atLimit < Self.budget(.seconds(1)), "recording \(Clipboard.maxRecordedContents) files took \(atLimit)")

            // ...and past it, skipped quickly instead of stalling for seconds.
            scratch.pasteboard.clearContents()
            scratch.pasteboard.writeObjects(fileURLs(10_000))
            let tenThousand = clock.measure { Fixture.poll() }
            #expect(History.shared.all.count == 2)
            #expect(tenThousand < Self.budget(.milliseconds(500)), "skipping 10,000 files took \(tenThousand)")

            // Fewer items, but more contents than the limit: skipped too.
            let rows = (0..<600).map { index in
                let row = NSPasteboardItem()
                row.setString("row \(index)", forType: .string)
                row.setString("<p>row \(index)</p>", forType: .html)
                return row
            }
            scratch.pasteboard.clearContents()
            scratch.pasteboard.writeObjects(rows)
            let manyContents = clock.measure { Fixture.poll() }
            #expect(History.shared.all.count == 2)
            #expect(manyContents < Self.budget(.milliseconds(500)), "skipping 1,200 contents took \(manyContents)")
        }

        private func fileURLs(_ count: Int) -> [NSURL] {
            (0..<count).map { NSURL(fileURLWithPath: "/tmp/clipkit-fixture-\(count)-\($0).txt") }
        }

        @Test func popupItemsBuildUnder100msFor200Items() async throws {
            let scratch = TestPasteboard()
            defer { scratch.release() }
            let kit = Fixture.kit(pasteboard: scratch)
            Fixture.start(kit)
            defer { kit.stop() }

            let context = Storage.shared.context
            for index in 0..<200 {
                let item = HistoryItem(contents: [
                    HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data("item \(index)".utf8))
                ])
                item.title = item.generateTitle()
                item.application = "com.apple.TextEdit"
                context.insert(item)
            }
            try context.save()

            let clock = ContinuousClock()
            let elapsed = try await clock.measure {
                try await History.shared.load()
                _ = kit.recent(limit: 200)
            }
            #expect(History.shared.items.count == 200)
            #expect(elapsed < Self.budget(.milliseconds(100)), "building 200 popup items took \(elapsed)")
        }
    }
}

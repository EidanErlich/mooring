import AppKit
import Foundation
import Observation
import Testing
@testable import ClipKit

@Suite
@MainActor
struct TextRecognitionTests {
    /// An image's title comes from text recognition, which runs in the background. The title must still be
    /// set on the main thread: the model belongs to the main context, and a write from another thread raced
    /// its saves (SwiftData's "Already have an objectID registered" crash).
    @Test(.timeLimit(.minutes(1)))
    func imageTitleIsSetOnTheMainThread() async throws {
        let image = try #require(NSImage(named: "NSBluetoothTemplate")?.tiffRepresentation)
        let item = HistoryItem(contents: [
            HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue, value: image)
        ])
        let setOnMainThread = await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = item.title
            } onChange: {
                continuation.resume(returning: Thread.isMainThread)
            }
            #expect(item.generateTitle() == "")
        }
        #expect(setOnMainThread)
    }
}

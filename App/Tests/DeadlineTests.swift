import Foundation
import Testing
@testable import Mooring

struct DeadlineTests {
    @Test func returnsAPromptResult() async {
        #expect(await withDeadline(.seconds(1)) { true } == true)
    }

    @Test func givesNilWhenTheOperationIgnoresTheDeadline() async {
        let start = Date()
        let value: Bool? = await withDeadline(.milliseconds(100)) {
            // Like an XPC call, this doesn't stop when cancelled.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { continuation.resume(returning: true) }
            }
        }
        #expect(value == nil)
        #expect(Date().timeIntervalSince(start) < 1)
    }
}

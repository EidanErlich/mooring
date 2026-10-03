import Foundation
import Testing
@testable import Mooring

@MainActor
struct HandlerGateTests {
    /// A link that arrives at launch waits for the handler instead of being lost.
    @Test func requestBeforeHandlerReadyIsServed() async {
        let fixture = RequestFixture()
        let gate = HandlerGate()
        let waiting = Task { await gate.handler() }
        // Let the task reach its wait before the handler exists.
        for _ in 0..<10 { await Task.yield() }

        gate.set(fixture.handler)

        #expect(await waiting.value === fixture.handler)
    }
}

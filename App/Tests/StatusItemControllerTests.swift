import AwakeKit
import Foundation
import Testing
@testable import Mooring

@MainActor
struct StatusItemControllerTests {
    /// Countdown ticks and setting changes redraw without arming another engine
    /// observation; only an engine change re-arms (one at a time, forever).
    @Test func timerRedrawsDoNotPileUpObservations() async {
        let engine = AwakeEngine(assertions: NullAssertions(), store: MemoryStore(), processes: NoProcesses(),
                                 lid: LidController(helper: FakeLidHelper()), settings: { AwakeSettings() })
        let controller = StatusItemController(engine: engine)
        #expect(controller.observationsArmed == 1)
        for _ in 0..<6 { controller.redraw() }
        #expect(controller.observationsArmed == 1)
        engine.acquire(id: "x", owner: .menu, reason: "r", level: .system, duration: 600)
        for _ in 0..<5 { await Task.yield() }
        #expect(controller.observationsArmed == 2)
    }
}

import Foundation
import MooringIPC
import Testing

@Suite struct WinPlanTests {
    private func badRequest(_ plan: WinPlan) -> WireError? {
        do {
            _ = try plan.validated()
            return nil
        } catch {
            return error as? WireError
        }
    }

    @Test func acceptsAValidPlan() throws {
        let plan = WinPlan(placements: [
            WinPlacement(app: "chrome", region: "right-half"),
            WinPlacement(app: "iterm", frame: WinFrame(x: 0, y: 0.5, w: 0.5, h: 0.5), screen: "left")
        ], launch: true)
        #expect(try plan.validated() == plan)
    }

    @Test func rejectsEmptyPlan() {
        let error = badRequest(WinPlan(placements: []))
        #expect(error?.code == .badRequest)
        #expect(error?.message == "A plan needs at least one placement")
    }

    @Test func rejectsOver32() throws {
        let one = WinPlacement(app: "chrome", region: "left-half")
        #expect(try WinPlan(placements: Array(repeating: one, count: 32)).validated().placements.count == 32)
        for count in [33, 1_000] {
            let error = badRequest(WinPlan(placements: Array(repeating: one, count: count)))
            #expect(error?.code == .badRequest)
            #expect(error?.message == "A plan can have at most 32 placements")
        }
    }

    @Test func rejectsRegionAndFrameTogether() {
        let both = WinPlacement(app: "chrome", region: "left-half", frame: WinFrame(x: 0, y: 0, w: 1, h: 1))
        let error = badRequest(WinPlan(placements: [both]))
        #expect(error?.code == .badRequest)
        #expect(error?.message == "chrome: give a region or a frame, not both")

        for neither in [WinPlacement(app: "chrome"), WinPlacement(app: "chrome", region: "  ")] {
            let missing = badRequest(WinPlan(placements: [neither]))
            #expect(missing?.code == .badRequest)
            #expect(missing?.message == "chrome: give a region or a frame")
        }
    }

    @Test func rejectsEmptyApp() {
        for app in ["", "   ", "\n"] {
            let error = badRequest(WinPlan(placements: [WinPlacement(app: app, region: "left-half")]))
            #expect(error?.code == .badRequest)
            #expect(error?.message == "Each placement needs an app")
        }
    }

    @Test func clampsFrame() throws {
        let plan = WinPlan(placements: [WinPlacement(app: "chrome", frame: WinFrame(x: -0.2, y: 0.25, w: 1.4, h: 1))])
        let frame = try #require(try plan.validated().placements.first?.frame)
        #expect(frame == WinFrame(x: 0, y: 0.25, w: 1, h: 1))
    }

    @Test func rejectsNaN() {
        let values: [Double] = [.nan, .infinity, -.infinity]
        for value in values {
            for frame in [WinFrame(x: value, y: 0, w: 1, h: 1), WinFrame(x: 0, y: value, w: 1, h: 1),
                          WinFrame(x: 0, y: 0, w: value, h: 1), WinFrame(x: 0, y: 0, w: 1, h: value)] {
                let error = badRequest(WinPlan(placements: [WinPlacement(app: "chrome", frame: frame)]))
                #expect(error?.code == .badRequest)
                #expect(error?.message == "chrome: frame values must be numbers")
            }
        }
    }

    @Test func trimsAppAndRegion() throws {
        let plan = WinPlan(placements: [WinPlacement(app: " chrome ", region: " left-half\n")])
        #expect(try plan.validated().placements == [WinPlacement(app: "chrome", region: "left-half")])
    }

    /// `win do` without `--app` sends this, and the app resolves it to the frontmost app other than Mooring.
    @Test func acceptsFrontmost() throws {
        #expect(WinPlacement.frontmostApp == "@frontmost")
        let plan = WinPlan(placements: [WinPlacement(app: WinPlacement.frontmostApp, region: "left-half")])
        #expect(try plan.validated().placements.first?.app == "@frontmost")
    }
}

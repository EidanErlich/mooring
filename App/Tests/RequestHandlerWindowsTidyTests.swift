import CoreGraphics
import Foundation
import MooringIPC
import Testing
@testable import Mooring

/// `RequestHandlerWindowsTests` continued: the ask's text, and saved layouts checked like any plan.
extension RequestHandlerWindowsTests {
    static let openLine = "May open apps that aren't running."

    /// Writes `layouts` straight to the arranger's file, as a hand edit would.
    func writeLayouts(_ layouts: [String: [WinPlacement]]) throws {
        let store = try #require(fixture.knobs.arranger?.layouts)
        try store.save(layouts)
    }

    @Test func askBodyIsTidied() {
        let long = String(repeating: "x", count: 60)
        let body = WindowApproval.body([WinPlacement(app: "Evil\u{7}\nApp\u{202E}", region: "maximize", title: long)])
        #expect(body == "EvilApp “\(String(repeating: "x", count: 39))…” → maximize")
        #expect(WindowApproval.body([WinPlacement(app: String(repeating: "a", count: 40), region: "center")])
            == "\(String(repeating: "a", count: 40)) → center")
        #expect(WindowApproval.body([Self.chromeRight], launch: true) == "chrome → right half\n\(Self.openLine)")
    }

    @Test func askSaysWhenAppsMayOpen() async throws {
        mode(.askFirst)
        approver.answers = [.deny, .deny, .deny]
        _ = await send(.winArrange(WinPlan(placements: [Self.chromeRight], launch: true)))
        _ = await arrange(Self.chromeRight)
        try writeLayouts(["coding": [Self.chromeRight]])
        _ = await send(.winLayout(WinLayoutArgs(action: "apply", name: "coding")))
        #expect(approver.calls.map(\.body) == [
            "chrome → right half\n\(Self.openLine)", "chrome → right half",
            "Layout “coding”: chrome → right half\n\(Self.openLine)"
        ])
        #expect(fake.calls.isEmpty)
    }

    @Test func layoutApplyIsValidated() async throws {
        mode(.askFirst)
        let many = (0...WinPlan.maxPlacements).map { _ in Self.slackLeft }
        try writeLayouts(["big": many, "blank": [WinPlacement(app: " ", region: "maximize")],
                          "wide": [WinPlacement(app: "slack", frame: WinFrame(x: -1, y: 0, w: 5, h: 0.5), screen: "0")]])
        let big = await send(.winLayout(WinLayoutArgs(action: "apply", name: "big")))
        #expect(wireFailure(big) == WireError(code: .badRequest, message: "Layout big is invalid: A plan can have at most 32 placements"))
        let blank = await send(.winLayout(WinLayoutArgs(action: "apply", name: "blank")))
        #expect(wireFailure(blank) == WireError(code: .badRequest, message: "Layout blank is invalid: Each placement needs an app"))
        #expect(approver.calls.isEmpty)
        #expect(fake.calls.isEmpty)

        // A frame out of range is clamped to the screen, as in any plan.
        approver.answers = [.allow]
        let wide = await send(.winLayout(WinLayoutArgs(action: "apply", name: "wide")))
        #expect(results(wide)?.map(\.status) == [.ok])
        #expect(frame(WindowFixture.slackMain) == CGRect(x: 0, y: 25, width: 1440, height: 437.5))
        #expect(approver.calls.first?.body == "Layout “wide”: slack → 100% × 50% at 0%, 0% on screen 0\n\(Self.openLine)")
    }

    /// A layout's apps are saved by bundle id; the ask names them, keeping an id it can't name.
    @Test func layoutAskNamesApps() async throws {
        mode(.askFirst)
        approver.answers = [.deny]
        try writeLayouts(["coding": [WinPlacement(app: "com.google.Chrome", region: "right-half"),
                                     WinPlacement(app: "com.example.gone", region: "left-half")]])
        _ = await send(.winLayout(WinLayoutArgs(action: "apply", name: "coding")))
        #expect(approver.calls.map(\.body) == [
            "Layout “coding”: Google Chrome → right half · com.example.gone → left half\n\(Self.openLine)"
        ])
        // The live names come from the installed app, without ".app".
        #expect(AppLocator.displayName(for: "com.apple.finder") == "Finder")
        #expect(AppLocator.displayName(for: "com.example.gone") == "com.example.gone")
    }
}

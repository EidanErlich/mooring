import CoreGraphics
import Foundation
import MooringIPC
import Testing
import WindowKit
@testable import Mooring

/// `ArrangerTests`' regions: a Windows-menu action that does more than set a frame isn't an agent's to run.
extension ArrangerTests {
    @Test func minimizeOthersIsRefused() async {
        for region in ["minimize-others", "minimize", "hide", "fullscreen", "next-space", "undo", "initial-frame"] {
            let results = await arrange(WinPlacement(app: "slack", region: region))
            #expect(results == [WinPlacementResult(app: "slack", status: .failed, reason: "region isn't available to agents")])
        }
        #expect(moves.isEmpty)
    }
}

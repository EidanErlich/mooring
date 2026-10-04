import CoreGraphics
import Foundation
import MooringIPC
import Testing
import WindowKit
@testable import Mooring

/// `ArrangerTests`' title matching: an exact title (any case) wins over titles that only contain it.
extension ArrangerTests {
    static let githubHome: CGWindowID = 1013
    static let githubPulls: CGWindowID = 1014

    /// Chrome with two GitHub windows, "GitHub - Pull requests" in front.
    func addGitHubWindows(home: String = "GitHub", pulls: String = "GitHub - Pull requests") {
        guard let index = fake.appList.firstIndex(where: { $0.pid == WindowFixture.chrome }) else { return }
        fake.appList[index].windows.insert(contentsOf: [
            WindowFixture.window(Self.githubPulls, WindowFixture.chrome, pulls, CGRect(x: 300, y: 200, width: 800, height: 600)),
            WindowFixture.window(Self.githubHome, WindowFixture.chrome, home, CGRect(x: 350, y: 250, width: 800, height: 600))
        ], at: 0)
    }

    @Test func exactTitleBeatsSubstring() async {
        addGitHubWindows()
        let results = await arrange(WinPlacement(app: "chrome", region: "left-half", title: "github"))
        #expect(results.map(\.status) == [.ok])
        #expect(frame(Self.githubHome) == CGRect(x: 0, y: 25, width: 720, height: 875))
        #expect(frame(Self.githubPulls) == CGRect(x: 300, y: 200, width: 800, height: 600))

        // With no exact title, a substring still picks the one window that has it.
        let pulls = await arrange(WinPlacement(app: "chrome", region: "right-half", title: "pull"))
        #expect(pulls.map(\.status) == [.ok])
        #expect(frame(Self.githubPulls) == CGRect(x: 720, y: 25, width: 720, height: 875))
    }

    @Test func twoExactTitlesAmbiguous() async {
        addGitHubWindows(home: "GitHub", pulls: "github")
        let results = await arrange(WinPlacement(app: "chrome", region: "left-half", title: "GitHub"))
        #expect(results == [WinPlacementResult(app: "chrome", status: .ambiguous, candidates: ["github", "GitHub"],
                                               reason: "matches several windows: github, GitHub")])
        #expect(moves.isEmpty)
    }
}

import AwakeKit
import Testing

struct LidApprovalTests {
    private func decide(_ setting: AgentLidApproval, agent: String? = "Claude Code", hasEnd: Bool, allowed: [String] = []) -> LidDecision {
        LidApproval.decide(setting: setting, agentName: agent, hasEnd: hasEnd, alwaysAllowed: allowed)
    }

    @Test func askWhenOpenEndedAllowsRequestsWithAnEnd() {
        #expect(decide(.askWhenOpenEnded, hasEnd: true) == .allow)
    }

    @Test func askWhenOpenEndedAsksWithoutAnEnd() {
        #expect(decide(.askWhenOpenEnded, hasEnd: false) == .ask)
    }

    @Test func alwaysAskAsksWithAnEnd() {
        #expect(decide(.alwaysAsk, hasEnd: true) == .ask)
    }

    @Test func alwaysAskAsksWithoutAnEnd() {
        #expect(decide(.alwaysAsk, hasEnd: false) == .ask)
    }

    @Test func alwaysAllowAllowsWithAnEnd() {
        #expect(decide(.alwaysAllow, hasEnd: true) == .allow)
    }

    @Test func alwaysAllowAllowsWithoutAnEnd() {
        #expect(decide(.alwaysAllow, hasEnd: false) == .allow)
    }

    @Test func neverRefusesWithAnEnd() {
        #expect(decide(.never, hasEnd: true) == .refuse)
    }

    @Test func neverRefusesWithoutAnEnd() {
        #expect(decide(.never, hasEnd: false) == .refuse)
    }

    @Test func peopleAreAlwaysAllowed() {
        for setting in AgentLidApproval.allCases {
            for hasEnd in [true, false] {
                #expect(decide(setting, agent: nil, hasEnd: hasEnd) == .allow)
            }
        }
    }

    @Test func alwaysAllowedSkipsTheAsk() {
        #expect(decide(.askWhenOpenEnded, hasEnd: false, allowed: ["Claude Code"]) == .allow)
        #expect(decide(.alwaysAsk, hasEnd: true, allowed: ["Claude Code"]) == .allow)
        #expect(decide(.alwaysAsk, hasEnd: false, allowed: ["Claude Code"]) == .allow)
    }

    @Test func otherAgentsStillAsk() {
        #expect(decide(.alwaysAsk, hasEnd: true, allowed: ["Codex"]) == .ask)
    }

    @Test func neverBeatsAlwaysAllowed() {
        #expect(decide(.never, hasEnd: true, allowed: ["Claude Code"]) == .refuse)
        #expect(decide(.never, hasEnd: false, allowed: ["Claude Code"]) == .refuse)
    }
}

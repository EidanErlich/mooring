import AwakeKit
import Foundation
import MooringIPC

/// Runs one piece of work at a time, in the order they arrive: arrangements never interleave their moves.
@MainActor
final class SerialLock {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T>(_ work: @MainActor () async throws -> T) async rethrows -> T {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
        // The lock passes straight to the next waiter, so nothing can slip in between.
        defer {
            if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        }
        return try await work()
    }
}

extension RequestHandler {
    /// The reply to a `win.*` request. An MCP client's plan or layout names the client.
    func windowsResult(_ args: RequestArgs, from caller: Caller) async throws -> ResponseResult {
        switch args {
        case .winList: .winList(try winList())
        case .winArrange(let plan): .winArrange(try await winArrange(plan, from: identified(caller, client: plan.client)))
        case .winUndo: .winUndo(try await winUndo(from: caller))
        case .winLayout(let args): .winLayout(try await winLayout(args, from: identified(caller, client: args.client)))
        default: throw WireError(code: .internal, message: "Not a window request")
        }
    }

    /// `win.list`: read-only, so it never asks.
    func winList() throws -> WinListResult {
        try runningArranger().list()
    }

    /// `win.arrange`, which `win do` also sends as a one-placement plan.
    func winArrange(_ plan: WinPlan, from caller: Caller) async throws -> WinArrangeResult {
        _ = try runningArranger()
        let agent = try agentToAsk(caller)
        let plan = try plan.validated()
        if let agent {
            try await askToArrange(agent, count: plan.placements.count, body: WindowApproval.body(plan.placements))
        }
        return try await windowLock.run { try await runningArranger().arrange(plan) }
    }

    /// `win.undo`: an agent set to Off is refused, but undo never asks.
    func winUndo(from caller: Caller) async throws -> WinArrangeResult {
        _ = try runningArranger()
        _ = try agentToAsk(caller)
        return try await windowLock.run {
            guard let result = try await runningArranger().undo() else {
                throw WireError(code: .notFound, message: "Nothing to undo")
            }
            return result
        }
    }

    /// `win.layout`: `list` is read-only; `apply` is an arrangement and asks; `save` and `delete` don't ask.
    func winLayout(_ args: WinLayoutArgs, from caller: Caller) async throws -> WinLayoutResult {
        let arranger = try runningArranger()
        let action = args.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if action == "list" { return try await arranger.layout(args) }
        let agent = try agentToAsk(caller)
        // A layout that doesn't exist (or a missing name) is left to `layout` to report, without asking.
        let name = args.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if action == "apply", let agent, let placements = try arranger.layouts.load()[name] {
            let body = "Layout “\(name)”: \(WindowApproval.body(placements))"
            try await askToArrange(agent, count: placements.count, body: body)
        }
        return try await windowLock.run { try await runningArranger().layout(args) }
    }

    /// The arranger, or `denied` unless Windows is on: off means off.
    private func runningArranger() throws -> Arranger {
        guard windowsState() == .on, let arranger = arranger() else {
            throw WireError(code: .denied, message: WindowApproval.windowsOff)
        }
        return arranger
    }

    /// The agent to ask on behalf of, or nil when nobody needs asking: a person, or agents set to Automatic.
    /// Agents set to Off are refused.
    private func agentToAsk(_ caller: Caller) throws -> String? {
        guard let agent = agentProcess(of: caller)?.name else { return nil }
        switch settings().agentWindows {
        case .automatic: return nil
        case .askFirst: return agent
        case .off: throw WireError(code: .denied, message: WindowApproval.agentsOff)
        }
    }

    /// Asks the person and returns only on Allow. Asks run side by side, each waiting for its own answer.
    private func askToArrange(_ agent: String, count: Int, body: String) async throws {
        let answer = await windowApprover.ask(title: WindowApproval.title(agent: agent, count: count), body: body)
        switch answer {
        case .allow: return
        case .deny: throw WireError(code: .denied, message: WindowApproval.denied)
        case .timeout: throw WireError(code: .denied, message: WindowApproval.timeout)
        case .unavailable: throw WireError(code: .denied, message: WindowApproval.unavailable)
        }
    }
}

import AwakeKit
import Foundation
import MooringIPC

/// Runs one piece of work at a time, in the order they arrive: arrangements never interleave their moves.
@MainActor
final class SerialLock {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// How many are waiting for their turn.
    var waiting: Int { waiters.count }

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
    /// The reply to a `win.*` request. A request naming an MCP client comes from that client, an agent.
    func windowsResult(_ args: RequestArgs, from caller: Caller) async throws -> ResponseResult {
        switch args {
        case .winList: .winList(try winList())
        case .winArrange(let plan): .winArrange(try await winArrange(plan, from: identified(caller, client: plan.client)))
        case .winUndo(let args): .winUndo(try await winUndo(from: identified(caller, client: args.client)))
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
        return try await onItsTurn(for: caller) { await $0.arrange(plan) }
    }

    /// `win.undo`: an agent set to Off is refused, but undo never asks.
    func winUndo(from caller: Caller) async throws -> WinArrangeResult {
        _ = try runningArranger()
        _ = try agentToAsk(caller)
        return try await onItsTurn(for: caller) { arranger in
            guard let result = await arranger.undo() else { throw WireError(code: .notFound, message: "Nothing to undo") }
            return result
        }
    }

    /// `win.layout`: `list` is read-only; `apply` is an arrangement and asks; `save` and `delete` don't ask.
    /// `apply` moves the placements read (and shown in the ask) up front, whatever is saved meanwhile.
    func winLayout(_ args: WinLayoutArgs, from caller: Caller) async throws -> WinLayoutResult {
        let arranger = try runningArranger()
        let action = args.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if action == "list" { return try await arranger.layout(args) }
        let agent = try agentToAsk(caller)
        let name = args.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard action == "apply", !name.isEmpty, let placements = try arranger.layouts.load()[name] else {
            // Save, delete, and an apply `layout` refuses (no name, or no such layout), which is never asked about.
            return try await onItsTurn(for: caller) { try await $0.layout(args) }
        }
        if let agent {
            try await askToArrange(agent, count: placements.count, body: "Layout “\(name)”: \(WindowApproval.body(placements))")
        }
        return try await onItsTurn(for: caller) { arranger in
            let result = await arranger.apply(layout: placements)
            return WinLayoutResult(names: (try? arranger.layouts.load().keys.sorted()) ?? [], arrange: result)
        }
    }

    /// Runs `work` once no other arrangement is applying, checking again that Windows is on and, for an agent, that
    /// agents aren't Off: either may have changed while the request asked or waited its turn.
    private func onItsTurn<T>(for caller: Caller, _ work: (Arranger) async throws -> T) async throws -> T {
        try await windowLock.run {
            let arranger = try runningArranger()
            if agentProcess(of: caller) != nil && settings().agentWindows == .off {
                throw WireError(code: .denied, message: WindowApproval.agentsOff)
            }
            return try await work(arranger)
        }
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

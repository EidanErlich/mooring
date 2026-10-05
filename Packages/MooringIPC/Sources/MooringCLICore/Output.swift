import Foundation
import MooringIPC

/// The one-line JSON the CLI prints for its own failures (usage errors and an app that can't be used).
enum CLIJSON {
    /// `{"ok":false,"error":{"code":…,"message":…}}` and a newline, with `message` escaped.
    static func errorLine(code: String, message: String) -> String {
        #"{"ok":false,"error":{"code":"\#(code)","message":\#(quoted(message))}}"# + "\n"
    }

    private static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode([text]), let array = String(bytes: data, encoding: .utf8) else { return #""""# }
        return String(array.dropFirst().dropLast())
    }
}

/// Human-readable text for the CLI's output.
enum CLIText {
    // Same formatting as `DurationText.remaining` in Packages/AwakeKit/Sources/AwakeKit/StatusText.swift; keep them identical.
    /// "45m", "2h" or "1h 12m", rounded up to whole minutes; a negative time reads as "0m". Matches the app's `DurationText.remaining`.
    static func remaining(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.up))
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(rest)m"
        }
    }

    /// How long a lease lasts: "until turned off", "while running", "while running · 4h cap" or "1h 12m left";
    /// "waiting for your approval" while it hasn't been approved yet.
    static func timeText(_ lease: LeaseInfo, now: Date) -> String {
        if lease.pendingApproval { return "waiting for your approval" }
        return switch (lease.expiresAt, lease.watchPid) {
        case (nil, nil): "until turned off"
        case (nil, _?): "while running"
        case (let expiry?, nil): "\(remaining(expiry.timeIntervalSince(now))) left"
        case (let expiry?, _?): "while running · \(remaining(expiry.timeIntervalSince(now))) cap"
        }
    }

    /// The success line for a request's result.
    static func human(_ result: ResponseResult, for args: RequestArgs, now: Date, processes: any ProcessTable) -> String {
        switch (result, args) {
        case (.acquire(let acquired), .acquire(let request)):
            acquire(acquired, kind: request.kind, now: now, processes: processes)
        case (.renew(let lease), _): "Renewed \(lease.id) · \(timeText(lease, now: now))"
        case (.release(let released), .release(let request)): release(released, request: request, now: now)
        case (.status(let status), _): StatusText.human(status, now: now)
        case (.notify(let result), _): result.posted ? "Notified" : "Not notified"
        case (.winList(let list), _): WinText.list(list)
        case (.winArrange(let arranged), _), (.winUndo(let arranged), _): WinText.arrange(arranged.results)
        case (.winLayout(let layout), .winLayout(let request)): WinText.layout(layout, request: request)
        default: "Done"
        }
    }

    private static func acquire(_ result: AcquireResult, kind: AcquireKind, now: Date, processes: any ProcessTable) -> String {
        let lease = result.lease
        let time = acquireTimeText(lease, now: now, processes: processes)
        var line = switch kind {
        case .on: "On · \(time)"
        case .anchor: "Anchored \(lease.id) · \(time)"
        case .lease: "Lease \(lease.id) · \(time)"
        }
        if let level = WireText.parseLevel(lease.level) {
            if level.display { line += " · screen on" }
            if level.lid { line += " · lid mode" }
        }
        if result.clamped, let expiry = lease.expiresAt {
            line += " (capped at \(remaining(expiry.timeIntervalSince(now))))"
        }
        return line
    }

    /// `timeText`, but a watched process is named: "while Claude Code (80) runs · 4h cap", or "while process 80 runs"
    /// when the process is already gone.
    private static func acquireTimeText(_ lease: LeaseInfo, now: Date, processes: any ProcessTable) -> String {
        guard let pid = lease.watchPid else { return timeText(lease, now: now) }
        let who = processes.entry(pid).map { "\(ProcessTree.agentName(for: $0, in: processes)) (\(pid))" } ?? "process \(pid)"
        let watching = "while \(who) runs"
        guard let expiry = lease.expiresAt else { return watching }
        return "\(watching) · \(remaining(expiry.timeIntervalSince(now))) cap"
    }

    private static func release(_ result: ReleaseResult, request: ReleaseArgs, now: Date) -> String {
        let name = request.id ?? "lease"
        switch request.kind {
        case .off: return result.released ? "Off" : "Already off"
        case .lease:
            guard result.released else { return "\(name) wasn't active" }
            guard let after = request.after, let expiresAt = result.expiresAt else { return "Released \(name)" }
            return releaseAfter(name, after: after, expiresAt: expiresAt, now: now)
        }
    }

    /// How much earlier than `now + after` a lease must end to count as already ending sooner: more than the reply's trip back.
    private static let replyLatency: TimeInterval = 2

    /// "job ends in 2m", or "job already ends sooner, in 1m" when `--after` left an earlier expiry alone. An app from before
    /// `ReleaseResult.expiresAt` doesn't say when the lease ends, so the caller prints "Released job" for it instead.
    private static func releaseAfter(_ name: String, after: TimeInterval, expiresAt: Date, now: Date) -> String {
        let left = remaining(expiresAt.timeIntervalSince(now))
        guard expiresAt < now.addingTimeInterval(after - replyLatency) else { return "\(name) ends in \(left)" }
        return "\(name) already ends sooner, in \(left)"
    }
}

public enum StatusText {
    /// The reasons the app reports for holding something back, in the order they are listed, with their wording.
    private static let pauses: [(key: String, text: String)] = [
        ("lowBatteryAll", "everything (battery low)"),
        ("lowBatteryLid", "lid mode (battery low)"),
        ("thermal", "lid mode (Mac too warm)"),
        ("lidNeedsAC", "lid mode (needs power)")
    ]

    /// The `mooring status` block: summary, leases in two padded columns, power and system line, and what is paused.
    public static func human(_ status: StatusResult, now: Date) -> String {
        var lines = [status.summary]
        lines.append(status.leases.isEmpty ? "No leases" : "Leases (\(status.leases.count))")
        let ownerWidth = (status.leases.map(\.owner.name.count).max() ?? 0) + 3
        let reasonWidth = (status.leases.map(\.reason.count).max() ?? 0) + 3
        for lease in status.leases {
            let line = "  " + pad(lease.owner.name, to: ownerWidth) + pad(lease.reason, to: reasonWidth)
                + CLIText.timeText(lease, now: now)
            lines.append(line)
        }
        lines.append(systemLine(status))
        let paused = pauses.filter { status.suspensions.contains($0.key) }.map(\.text)
        if !paused.isEmpty { lines.append("Paused: " + paused.joined(separator: ", ")) }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func systemLine(_ status: StatusResult) -> String {
        var parts: [String]
        if status.power.onAC {
            parts = ["On power"]
        } else {
            parts = [status.power.batteryPercent.map { "Battery \($0)%" } ?? "Battery"]
        }
        parts.append("Thermal \(status.thermal)")
        if let closed = status.lidClosed { parts.append(closed ? "Lid closed" : "Lid open") }
        parts.append("Helper \(status.helper)")
        return parts.joined(separator: " · ")
    }

    private static func pad(_ text: String, to width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - text.count))
    }
}

/// Human-readable text for the `win` commands.
enum WinText {
    static let nothingToUndo = "Nothing to undo"
    /// The status text of `not_running`, and the app's reason when it has nothing more to say.
    private static let notRunning = "isn't running"

    /// 0 when every placement landed, 2 when any didn't; everything else is 0.
    static func exitStatus(for result: ResponseResult) -> Int32 {
        let results: [WinPlacementResult]
        switch result {
        case .winArrange(let arranged), .winUndo(let arranged): results = arranged.results
        case .winLayout(let layout): results = layout.arrange?.results ?? []
        default: return 0
        }
        return results.allSatisfy { $0.status == .ok } ? 0 : 2
    }

    /// One line per placement: "iterm ok (was minimized, restored)", "code ambiguous: matches several apps: Visual Studio
    /// Code, Xcode", "notes isn't running".
    static func arrange(_ results: [WinPlacementResult]) -> String {
        results.map(line).joined(separator: "\n")
    }

    private static func line(_ result: WinPlacementResult) -> String {
        var line = "\(result.app) \(statusText(result.status))"
        if let detail = detail(result) { line += ": \(detail)" }
        if let note = result.note, !note.isEmpty { line += " (\(note))" }
        return line
    }

    private static func statusText(_ status: WinStatus) -> String {
        switch status {
        case .ok: "ok"
        case .partial: "partial"
        case .ambiguous: "ambiguous"
        case .notRunning: notRunning
        case .notFound: "not found"
        case .failed: "failed"
        }
    }

    private static func detail(_ result: WinPlacementResult) -> String? {
        switch result.status {
        case .ok: return nil
        case .partial: return result.frame.map { "stopped at \(size($0))" }
        case .ambiguous:
            if let reason = result.reason, !reason.isEmpty { return reason }
            guard let names = result.candidates, !names.isEmpty else { return nil }
            return "matches several: \(names.joined(separator: ", "))"
        case .notRunning: return result.reason == notRunning ? nil : result.reason
        default: return result.reason
        }
    }

    /// Apps with their windows, then the screens.
    static func list(_ list: WinListResult) -> String {
        var lines: [String] = []
        for app in list.apps {
            lines.append(app.name)
            if app.windows.isEmpty { lines.append("  no windows") }
            lines += app.windows.map { "  " + windowLine($0) }
        }
        lines.append("Screens")
        lines += list.screens.map { "  \($0.index) \($0.name) (\($0.position)) · \(origin($0.visibleFrame)) \(size($0.visibleFrame))" }
        return lines.joined(separator: "\n")
    }

    private static func windowLine(_ window: WinWindowInfo) -> String {
        var parts = [window.title.isEmpty ? "(untitled)" : window.title]
        parts.append("\(origin(window.frame)) \(size(window.frame))")
        parts.append("screen \(window.screen)")
        if window.minimized { parts.append("minimized") }
        if window.fullScreen { parts.append("full screen") }
        return parts.joined(separator: " · ")
    }

    static func layout(_ result: WinLayoutResult, request: WinLayoutArgs) -> String {
        let name = request.name ?? "layout"
        switch request.action {
        case "save": return "Saved \(name)"
        case "delete": return "Deleted \(name)"
        case "apply": return result.arrange.map { arrange($0.results) } ?? "Applied \(name)"
        default: return result.names.isEmpty ? "No saved layouts" : result.names.joined(separator: "\n")
        }
    }

    private static func origin(_ frame: WinFrame) -> String { "\(whole(frame.x)),\(whole(frame.y))" }
    private static func size(_ frame: WinFrame) -> String { "\(whole(frame.w))x\(whole(frame.h))" }
    private static func whole(_ value: Double) -> Int { Int(value.rounded()) }
}

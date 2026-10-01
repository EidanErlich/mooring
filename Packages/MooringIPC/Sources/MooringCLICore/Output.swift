import Foundation
import MooringIPC

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

    /// How long a lease lasts: "until turned off", "while running", "while running · 4h cap" or "1h 12m left".
    static func timeText(_ lease: LeaseInfo, now: Date) -> String {
        switch (lease.expiresAt, lease.watchPid) {
        case (nil, nil): "until turned off"
        case (nil, _?): "while running"
        case (let expiry?, nil): "\(remaining(expiry.timeIntervalSince(now))) left"
        case (let expiry?, _?): "while running · \(remaining(expiry.timeIntervalSince(now))) cap"
        }
    }

    /// The success line for a request's result.
    static func human(_ result: ResponseResult, for args: RequestArgs, now: Date) -> String {
        switch (result, args) {
        case (.acquire(let acquired), .acquire(let request)): acquire(acquired, kind: request.kind, now: now)
        case (.renew(let lease), _): "Renewed \(lease.id) · \(timeText(lease, now: now))"
        case (.release(let released), .release(let request)): release(released, request: request)
        case (.status(let status), _): StatusText.human(status, now: now)
        default: "Done"
        }
    }

    private static func acquire(_ result: AcquireResult, kind: AcquireKind, now: Date) -> String {
        let lease = result.lease
        let time = timeText(lease, now: now)
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

    private static func release(_ result: ReleaseResult, request: ReleaseArgs) -> String {
        let name = request.id ?? "lease"
        switch request.kind {
        case .off: return result.released ? "Off" : "Already off"
        case .lease: return result.released ? "Released \(name)" : "\(name) wasn't active"
        }
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

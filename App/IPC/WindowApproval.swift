import Foundation
import MooringIPC
import UserNotifications

/// How the person answered an ask to arrange windows.
enum WindowAnswer: Equatable, Sendable {
    case allow, deny, timeout, unavailable
}

/// Asks the person before an agent arranges windows, when agents are set to Ask first.
@MainActor
protocol WindowApproving: AnyObject {
    func ask(title: String, body: String) async -> WindowAnswer
}

/// The `denied` replies of `win.*` and the ask's notification text (stage 3b spec, "Ask first").
enum WindowApproval {
    static let windowsOff = "Windows is off. Turn it on in Mooring (Windows › Turn On…)."
    static let agentsOff = "Window arrangement by agents is off in Settings"
    static let denied = "Window arrangement not approved (denied)"
    static let timeout = "Window arrangement not approved (no answer in 60 s)"
    static let unavailable = "Turn on notifications for Mooring in System Settings to approve window arrangement"
    /// The most placements the body names; the rest are counted.
    static let listedPlacements = 6
    /// The most characters of an agent's app or title the body shows.
    static let longestName = 40
    /// The body's last line when the arrangement may open apps.
    static let mayOpenApps = "May open apps that aren't running."

    /// "<Agent> wants to arrange N windows".
    static func title(agent: String, count: Int) -> String {
        "\(agent) wants to arrange \(count) \(count == 1 ? "window" : "windows")"
    }

    /// "chrome → right half · iterm → bottom left · …", naming at most `listedPlacements`, then `mayOpenApps` on a line
    /// of its own when `launch`.
    static func body(_ placements: [WinPlacement], launch: Bool = false) -> String {
        var parts = placements.prefix(listedPlacements).map(describe)
        if placements.count > listedPlacements { parts.append("and \(placements.count - listedPlacements) more") }
        let body = parts.joined(separator: " · ")
        return launch ? body + "\n" + mayOpenApps : body
    }

    /// An agent's text as the body shows it: without control or formatting characters (so no line breaks or
    /// direction overrides), and at most `longestName` characters.
    static func shown(_ text: String) -> String {
        let hidden: Set<Unicode.GeneralCategory> = [.control, .format, .lineSeparator, .paragraphSeparator]
        let kept = String(String.UnicodeScalarView(text.unicodeScalars.filter { !hidden.contains($0.properties.generalCategory) }))
        return kept.count > longestName ? String(kept.prefix(longestName - 1)) + "…" : kept
    }

    private static func describe(_ placement: WinPlacement) -> String {
        var app = placement.app == WinPlacement.frontmostApp ? "the frontmost app" : shown(placement.app)
        if let title = placement.title, !title.isEmpty { app += " “\(shown(title))”" }
        var target = placement.region.map { $0.replacingOccurrences(of: "-", with: " ") } ?? ""
        if let frame = placement.frame {
            target = "\(percent(frame.w)) × \(percent(frame.h)) at \(percent(frame.x)), \(percent(frame.y))"
        }
        switch placement.screen?.lowercased() {
        case nil: break
        case let screen? where ["main", "left", "right"].contains(screen): target += " on the \(screen) screen"
        case let screen?: target += " on screen \(screen)"
        }
        return "\(app) → \(target)"
    }

    private static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

/// Posts an actionable notification per ask and waits for Allow or Deny, up to `timeout`; the window-arrangement
/// sibling of `LidApprovalCenter`, sharing its poster. Each ask resolves exactly once: by its response or the timeout.
@MainActor
final class WindowApprovalCenter: WindowApproving {
    nonisolated static let categoryID = "mooring.window-approval"
    nonisolated static let allowAction = "mooring.allow-arrange"
    nonisolated static let denyAction = "mooring.deny-arrange"

    static let category = UNNotificationCategory(
        identifier: categoryID,
        actions: [
            UNNotificationAction(identifier: allowAction, title: "Allow"),
            UNNotificationAction(identifier: denyAction, title: "Deny", options: [.destructive])
        ],
        intentIdentifiers: []
    )

    private let poster: NotificationPosting
    private let timeout: Duration
    private var waiting: [String: Waiting] = [:]

    private struct Waiting {
        let continuation: CheckedContinuation<WindowAnswer, Never>
        let timer: Task<Void, Never>
    }

    init(poster: NotificationPosting, timeout: Duration = .seconds(60)) {
        self.poster = poster
        self.timeout = timeout
    }

    /// The answer an action gives; nil for the body tap and dismissal, which the timeout covers.
    nonisolated static func answer(forAction action: String) -> WindowAnswer? {
        switch action {
        case allowAction: .allow
        case denyAction: .deny
        default: nil
        }
    }

    func ask(title: String, body: String) async -> WindowAnswer {
        guard await poster.authorize() else { return .unavailable }
        let id = "win-\(UUID().uuidString)"
        return await withCheckedContinuation { continuation in
            // Registered before posting, so even an instant response finds it.
            let timer = Task { [weak self, timeout] in
                do { try await Task.sleep(for: timeout) } catch { return }
                self?.resolve(id, with: .timeout)
            }
            waiting[id] = Waiting(continuation: continuation, timer: timer)
            Task {
                await poster.post(id: id, title: title, body: body, userInfo: [:], category: Self.categoryID)
                // Resolved while posting: don't leave buttons that do nothing.
                if waiting[id] == nil { poster.withdraw(id: id) }
            }
        }
    }

    /// Withdraws asks that nothing waits for, such as those left from before a restart.
    func removeStaleApprovals() async {
        for id in await poster.deliveredApprovalIDs(category: Self.categoryID) where waiting[id] == nil {
            poster.withdraw(id: id)
        }
    }

    /// A notification response, forwarded by the app's notification delegate.
    func handle(actionIdentifier: String, requestID: String) {
        guard let answer = Self.answer(forAction: actionIdentifier) else { return }
        resolve(requestID, with: answer)
    }

    /// Resumes the ask once; a late or unknown id is ignored.
    private func resolve(_ id: String, with answer: WindowAnswer) {
        guard let entry = waiting.removeValue(forKey: id) else { return }
        entry.timer.cancel()
        if answer == .timeout { poster.withdraw(id: id) }
        entry.continuation.resume(returning: answer)
    }
}

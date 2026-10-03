import AwakeKit
import Foundation
import MooringIPC

extension RequestHandler {
    /// The least time between two of one agent's notifications.
    static let notifyInterval: TimeInterval = 30
    /// The longest a notification's own title and body may be, after cleaning.
    private static let notifyTitleLimit = 80
    private static let notifyBodyLimit = 300
    /// Whom a person's notifications come from.
    static let personName = MCPClientName.personName

    /// `mooring notify`: posts "<Name>: <title>" with the body. An agent may be turned off in Settings and is
    /// rate-limited by name; an MCP client also by its pid, since it picks its own name. A person is neither.
    func notify(_ args: NotifyArgs, from caller: Caller) async throws -> NotifyResult {
        let agent = agentProcess(of: caller)?.name
        if agent != nil && !settings().agentNotifications {
            throw WireError(code: .denied, message: "Notifications from agents are turned off in Settings")
        }
        let title = CallerPolicy.clean(args.title, limit: Self.notifyTitleLimit)
        guard !title.isEmpty else { throw WireError(code: .badRequest, message: "Missing title") }
        let body = CallerPolicy.clean(args.body ?? "", limit: Self.notifyBodyLimit)
        guard await poster.authorize() else { throw WireError(code: .denied, message: LidMessage.unavailable) }
        let name = agent ?? Self.personName
        // Checked and recorded after the last suspension, so two requests at once can't both pass.
        if agent != nil {
            var buckets = [name]
            if case .client = caller.identity { buckets.append("pid-\(caller.pid)") }
            try checkRate(buckets)
        }
        await poster.post(
            id: "notify-\(UUID().uuidString)", title: "\(name): \(title)", body: body, userInfo: [:], category: nil
        )
        return NotifyResult(posted: true)
    }

    /// Refuses unless every bucket's last notification is at least `notifyInterval` ago, then records them all.
    private func checkRate(_ buckets: [String]) throws {
        let current = now()
        let wait = buckets.compactMap { lastNotified[$0] }
            .map { Self.notifyInterval - current.timeIntervalSince($0) }
            .max() ?? 0
        if wait > 0 {
            throw WireError(code: .denied, message: "Rate-limited: try again in \(Int(wait.rounded(.up))) s")
        }
        for bucket in buckets { lastNotified[bucket] = current }
    }
}

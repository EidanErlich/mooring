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
    private static let personName = "Terminal"

    /// `mooring notify`: posts "<Name>: <title>" with the body. An agent may be turned off in Settings and is
    /// rate-limited; a person is neither.
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
            let current = now()
            if let last = lastNotified[name], current.timeIntervalSince(last) < Self.notifyInterval {
                let wait = Int((Self.notifyInterval - current.timeIntervalSince(last)).rounded(.up))
                throw WireError(code: .denied, message: "Rate-limited: try again in \(wait) s")
            }
            lastNotified[name] = current
        }
        await poster.post(
            id: "notify-\(UUID().uuidString)", title: "\(name): \(title)", body: body, userInfo: [:], category: nil
        )
        return NotifyResult(posted: true)
    }
}

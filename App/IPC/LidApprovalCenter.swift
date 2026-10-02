import Foundation
import Observation
import UserNotifications

/// How the user answered a lid-mode approval (stage 2c-1 spec, "Asking").
enum LidAnswer: Equatable, Sendable {
    case allowOnce, alwaysAllow, deny, timeout, unavailable
}

/// Asks the user before an agent gets open-ended lid mode.
@MainActor
protocol LidApproving: AnyObject {
    func ask(leaseID: String, agent: String, body: String) async -> LidAnswer
    /// Lease ids whose ask is still unresolved.
    var pending: Set<String> { get }
}

/// Posts the approval notification. Tests use a fake; nothing real is posted there.
@MainActor
protocol NotificationPosting: AnyObject {
    /// Requests authorization if it hasn't been asked yet; true only if allowed.
    func authorize() async -> Bool
    /// "allowed", "notDetermined" or "denied"; nil if the settings can't be read.
    func notificationStatus() async -> String?
    func post(id: String, title: String, body: String, userInfo: [String: String]) async
    /// Removes a delivered notification whose ask is over.
    func withdraw(id: String)
}

/// `NotificationPosting` over `UNUserNotificationCenter`.
@MainActor
final class SystemNotificationPoster: NotificationPosting {
    private var center: UNUserNotificationCenter { .current() }

    func authorize() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func notificationStatus() async -> String? {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: "notDetermined"
        case .authorized, .provisional: "allowed"
        case .denied: "denied"
        @unknown default: nil
        }
    }

    func post(id: String, title: String, body: String, userInfo: [String: String]) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        content.categoryIdentifier = LidApprovalCenter.categoryID
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func withdraw(id: String) {
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}

/// Posts an actionable notification per ask and waits for the answer, up to
/// `timeout`. Each ask resolves exactly once: by its response or by the timeout.
@MainActor @Observable
final class LidApprovalCenter: LidApproving {
    nonisolated static let categoryID = "mooring.lid-approval"
    nonisolated static let allowOnceAction = "mooring.allow-once"
    nonisolated static let alwaysAllowAction = "mooring.always-allow"
    nonisolated static let denyAction = "mooring.deny"

    /// Category actions are static, so "Always allow" can't name the agent;
    /// the notification body starts with the agent's name instead.
    static let category = UNNotificationCategory(
        identifier: categoryID,
        actions: [
            UNNotificationAction(identifier: allowOnceAction, title: "Allow once"),
            UNNotificationAction(identifier: alwaysAllowAction, title: "Always allow this agent"),
            UNNotificationAction(identifier: denyAction, title: "Deny", options: [.destructive])
        ],
        intentIdentifiers: []
    )

    private(set) var pending: Set<String> = []

    @ObservationIgnored private let poster: NotificationPosting
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private var waiting: [String: Waiting] = [:]

    private struct Waiting {
        let leaseID: String
        let continuation: CheckedContinuation<LidAnswer, Never>
        let timer: Task<Void, Never>
    }

    init(poster: NotificationPosting = SystemNotificationPoster(), timeout: Duration = .seconds(60)) {
        self.poster = poster
        self.timeout = timeout
    }

    /// The answer an action gives; nil for the body tap and dismissal, which the timeout covers.
    nonisolated static func answer(forAction action: String) -> LidAnswer? {
        switch action {
        case allowOnceAction: .allowOnce
        case alwaysAllowAction: .alwaysAllow
        case denyAction: .deny
        default: nil
        }
    }

    func ask(leaseID: String, agent: String, body: String) async -> LidAnswer {
        guard await poster.authorize() else { return .unavailable }
        let id = "lid-\(leaseID)-\(UUID().uuidString)"
        let title = "\(agent) wants to keep your Mac awake with the lid closed"
        let text = "\(agent) · \(body)"
        return await withCheckedContinuation { continuation in
            // Registered before posting, so even an instant response finds it.
            let timer = Task { [weak self, timeout] in
                do { try await Task.sleep(for: timeout) } catch { return }
                self?.resolve(id, with: .timeout)
            }
            waiting[id] = Waiting(leaseID: leaseID, continuation: continuation, timer: timer)
            pending.insert(leaseID)
            Task {
                await poster.post(id: id, title: title, body: text, userInfo: ["leaseID": leaseID])
                // Resolved while posting: don't leave buttons that do nothing.
                if waiting[id] == nil { poster.withdraw(id: id) }
            }
        }
    }

    /// "allowed", "notDetermined" or "denied", for `mooring status` and `doctor`.
    func notificationStatus() async -> String? {
        await poster.notificationStatus()
    }

        /// A notification response, forwarded by the app's notification delegate.
    func handle(actionIdentifier: String, requestID: String) {
        guard let answer = Self.answer(forAction: actionIdentifier) else { return }
        resolve(requestID, with: answer)
    }

    /// Resumes the ask once; a late or unknown id is ignored.
    private func resolve(_ id: String, with answer: LidAnswer) {
        guard let entry = waiting.removeValue(forKey: id) else { return }
        entry.timer.cancel()
        pending = Set(waiting.values.map(\.leaseID))
        if answer == .timeout { poster.withdraw(id: id) }
        entry.continuation.resume(returning: answer)
    }
}

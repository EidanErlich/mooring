import AwakeKit
import Defaults
import UserNotifications
import os

/// Tells the user when a guardrail pauses awake (docs/SPEC.md 1.7). Permission
/// is requested the first time a notification is actually needed.
enum GuardrailNotifier {
    static func message(for suspension: Suspension, settings: AwakeSettings) -> (title: String, body: String) {
        switch suspension {
        case .lowBatteryLid:
            let threshold = settings.lidBatteryThreshold ?? 0
            return ("Lid mode paused",
                    "Battery is below \(threshold)%. The Mac stays awake, but will sleep if you close the lid. "
                        + "Lid mode resumes on power at \(threshold + 5)%.")
        case .lowBatteryAll:
            let threshold = settings.allBatteryThreshold ?? 0
            return ("Mooring paused",
                    "Battery is below \(threshold)%, so your Mac can sleep normally. Mooring resumes when you plug in.")
        case .thermal:
            return ("Lid mode paused",
                    "Your Mac is running hot with the lid closed. Lid mode resumes when it cools down.")
        case .lidNeedsAC:
            return ("Lid mode waits for power",
                    "Lid mode on battery is off in Settings. Plug in, or allow it in Mooring Settings → Lid & Battery.")
        }
    }

    @MainActor
    static func post(_ added: Set<Suspension>) {
        guard Defaults[.notifyGuardrails] else { return }
        let settings = Defaults[.awake]
        let messages = added.map { (id: "guardrail-\($0)", text: message(for: $0, settings: settings)) }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else {
                Logger(subsystem: "dev.mooring", category: "guardrail").notice("notifications not allowed")
                return
            }
            for message in messages {
                let content = UNMutableNotificationContent()
                content.title = message.text.title
                content.body = message.text.body
                try? await center.add(UNNotificationRequest(identifier: message.id, content: content, trigger: nil))
            }
        }
    }
}

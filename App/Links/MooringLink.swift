import Foundation
import MooringIPC

/// What a `mooring://` link asks for. Every action works on the menu session, like `mooring on` and `off`; a level
/// is its canonical name and a duration is in seconds, nil when the link doesn't give one.
enum LinkAction: Equatable {
    case on(level: String?, duration: TimeInterval?, reason: String?) // swiftlint:disable:this identifier_name
    case off
    /// Off if the menu session is on; otherwise on, with these parameters.
    case toggle(level: String?, duration: TimeInterval?, reason: String?)
}

/// Why a link can't be used. The link has no reply channel, so `message` is shown in a notification.
enum LinkError: Error, Equatable {
    case unknownAction(String)
    case badDuration
    case badLevel(String)

    var message: String {
        switch self {
        case .unknownAction(let action): "unknown action '\(action)'"
        case .badDuration: "'for' must look like 30m or 1h30m"
        case .badLevel(let level): "unknown level '\(level)'"
        }
    }
}

/// Parses `mooring://on`, `off` and `toggle` links, with `for`, `level` and `reason` taking the CLI's grammar.
enum MooringLink {
    static func parse(_ url: URL) -> Result<LinkAction, LinkError> {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // `mooring://on/` and `mooring:on` name the same action as `mooring://on`.
        let action = ((components?.host ?? "") + (components?.path ?? ""))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // The last of a repeated parameter wins; one with no value counts as missing.
        var params: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            params[item.name] = item.value
        }
        switch action.lowercased() {
        case "off":
            return .success(.off)
        case "on", "toggle":
            var duration: TimeInterval?
            if let text = params["for"] {
                guard let seconds = WireText.parseDuration(text) else { return .failure(.badDuration) }
                duration = seconds
            }
            var level: String?
            if let text = params["level"] {
                guard let flags = WireText.parseLevel(text) else { return .failure(.badLevel(text)) }
                level = WireText.levelName(display: flags.display, lid: flags.lid)
            }
            let reason = params["reason"].flatMap { $0.isEmpty ? nil : $0 }
            return .success(action.lowercased() == "on"
                ? .on(level: level, duration: duration, reason: reason)
                : .toggle(level: level, duration: duration, reason: reason))
        default:
            return .failure(.unknownAction(action))
        }
    }
}

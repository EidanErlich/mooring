import Foundation

/// Who is asking over the CLI socket.
public enum CallerKind: Sendable {
    /// The `mooring` CLI itself: may do anything the menu can.
    case trusted
    /// An agent or script naming its own lease: short and bounded; lid mode is decided by `LidApproval`.
    case named
}

public enum PolicyRefusal: Error, Equatable, Sendable {
    /// The request is malformed or breaks a naming rule.
    case badRequest(String)
    /// The request is well formed but not allowed.
    case denied(String)
}

/// The rules for what socket callers may do, kept apart from the engine so they can be tested alone.
public enum CallerPolicy {
    public static let maxNamedLease: TimeInterval = 4 * 3600
    public static let maxLeases = 32
    public static let reasonLimit = 80
    public static let agentNameLimit = 40

    /// Mirrors `AwakeEngine.menuLeaseID` and `lidSessionID` (main-actor isolated, so not usable here), plus the CLI's own.
    private static let reservedIDs: Set<String> = ["menu", "lid-session", "cli"]
    private static let reservedPrefixes = ["app-", "anchor-"]
    private static let idLimit = 64
    private static let idCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

    // swiftlint:disable function_parameter_count
    /// The duration to grant (nil = no expiry), or why the request is refused.
    public static func checkAcquire(
        kind: CallerKind, id: String, level: AwakeLevel, ttl: TimeInterval?, watched: Bool,
        liveLeaseCount: Int, exists: Bool
    ) -> Result<TimeInterval?, PolicyRefusal> {
        if kind == .named {
            if !isValidNamedID(id) { return .failure(.badRequest("Invalid lease id")) }
            if isReserved(id) { return .failure(.badRequest("\(id) is reserved")) }
        }
        if !exists && liveLeaseCount >= maxLeases {
            return .failure(.denied("Too many leases (\(maxLeases))"))
        }
        guard kind == .named else { return .success(ttl) }
        if ttl == nil && !watched {
            return .failure(.badRequest("A lease needs --ttl or --watch-pid"))
        }
        return .success(min(ttl ?? maxNamedLease, maxNamedLease))
    }
    // swiftlint:enable function_parameter_count

    /// 1 to 64 of letters, digits, `.`, `_` and `-`.
    public static func isValidNamedID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= idLimit
            && id.unicodeScalars.allSatisfy { idCharacters.contains($0) }
    }

    /// Ids the app uses for its own leases.
    public static func isReserved(_ id: String) -> Bool {
        reservedIDs.contains(id) || reservedPrefixes.contains { id.hasPrefix($0) }
    }

    public static func cleanReason(_ text: String) -> String {
        clean(text, limit: reasonLimit)
    }

    public static func cleanAgentName(_ text: String) -> String {
        clean(text, limit: agentNameLimit)
    }

    /// Drops control characters (newlines and tabs included), trims, then cuts to `limit` characters.
    public static func clean(_ text: String, limit: Int) -> String {
        let printable = String(String.UnicodeScalarView(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        return String(printable.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}

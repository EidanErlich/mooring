import Foundation

/// The code-signing requirement a client must meet to connect, read from the
/// helper's embedded Info.plist, where scripts/write-helper-requirement.sh put it.
enum ClientRequirement {
    static let infoKey = "SMAuthorizedClients"
    static let unsignedPlaceholder = "MOORING_UNSIGNED"

    private static let pattern = #"^identifier "dev\.mooring\.app" and certificate leaf = H"[0-9A-Fa-f]{40}"$"#

    /// Returns the requirement, or nil when the build had no signing certificate
    /// or the string is malformed. Nil means the helper accepts no one.
    static func load(from info: [String: Any]?) -> String? {
        guard let requirement = (info?[infoKey] as? [String])?.first,
              requirement.range(of: pattern, options: .regularExpression) != nil
        else { return nil }
        return requirement
    }
}

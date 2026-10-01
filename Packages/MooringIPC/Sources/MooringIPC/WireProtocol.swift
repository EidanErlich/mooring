import Foundation

/// The app ↔ CLI socket format (docs/SPEC.md 2.1). Every request and response
/// carries this value in its `v` field.
public enum WireProtocol {
    public static let version = 1

    /// Where the app listens and the CLI connects: `~/Library/Application Support/Mooring/mooring.sock`,
    /// kept well under the 104-byte `sockaddr_un` limit.
    public static var defaultSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Mooring/mooring.sock"
    }
}

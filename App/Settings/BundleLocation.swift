import Foundation

/// Where the running app sits, for features that write its path somewhere that outlives this launch.
enum BundleLocation {
    /// Shown beside the buttons that stay disabled while the app is in a transient location.
    static let moveCaption = "Move Mooring to Applications first"

    /// True when `url` is a place the app won't stay: Gatekeeper's randomized read-only copy (`AppTranslocation`) or a
    /// mounted disk image under `/Volumes`.
    static func isTransient(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/")
    }

    /// Whether the running app is in such a place.
    static var isRunningTransient: Bool { isTransient(Bundle.main.bundleURL) }
}

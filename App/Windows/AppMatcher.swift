import AppKit
import Foundation
import WindowKit

/// Which running app a plan's `app` means. Case-insensitive, by tier: an exact name or bundle id; then a prefix of the
/// name; then a substring of the name or of the bundle id's last component ("iterm" → iTerm2, "code" → Visual Studio
/// Code `com.microsoft.VSCode` and Xcode). The first tier with a match decides; two or more there is ambiguous.
enum AppMatcher {
    enum MatchResult: Equatable {
        case one(WSApp)
        case ambiguous([WSApp])
        case none
    }

    static func match(_ query: String, in apps: [WSApp]) -> MatchResult {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return .none }
        let tiers: [(WSApp) -> Bool] = [
            { $0.name.lowercased() == key || $0.bundleID?.lowercased() == key },
            { $0.name.lowercased().hasPrefix(key) },
            { $0.name.lowercased().contains(key) || lastComponent(of: $0.bundleID).contains(key) }
        ]
        for tier in tiers {
            let found = apps.filter(tier)
            if found.count == 1 {
                return .one(found[0])
            }
            if found.count > 1 {
                return .ambiguous(found)
            }
        }
        return .none
    }

    private static func lastComponent(of bundleID: String?) -> String {
        (bundleID?.split(separator: ".").last).map { $0.lowercased() } ?? ""
    }
}

/// The bundle id to open for an app that isn't running: a query that is an installed bundle id as is, or else the
/// `.app` of that name (any case) in the standard Applications folders.
enum AppLocator {
    static func bundleID(for query: String) -> String? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        if query.contains("."), NSWorkspace.shared.urlForApplication(withBundleIdentifier: query) != nil {
            return query
        }
        let wanted = (query.lowercased().hasSuffix(".app") ? query : query + ".app").lowercased()
        for directory in searchDirectories {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
                  let match = names.first(where: { $0.lowercased() == wanted }),
                  let bundleID = Bundle(url: directory.appendingPathComponent(match))?.bundleIdentifier
            else {
                continue
            }
            return bundleID
        }
        return nil
    }

    private static var searchDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } + [home.appendingPathComponent("Applications", isDirectory: true)]
    }
}

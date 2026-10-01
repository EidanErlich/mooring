import Foundation

enum CLIInstallerError: Error, Equatable {
    /// Something other than a symlink already sits at the link path, and we won't replace it.
    case notALink
}

extension CLIInstallerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notALink: "A file that isn't a link is already at ~/.local/bin/mooring. Move it away first."
        }
    }
}

/// Puts the bundled `mooring` binary on the user's PATH with a symlink in `~/.local/bin`.
enum CLIInstaller {
    enum State: Equatable {
        case installed
        case missing
        /// A link (or file) is there but doesn't lead to this app's binary; holds where it leads.
        case pointsElsewhere(String)
    }

    /// The line to add to `~/.zshrc` when `~/.local/bin` isn't on the shell's PATH.
    static let pathLine = "export PATH=\"$HOME/.local/bin:$PATH\""

    static var defaultLink: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/mooring")
    }

    static var bundledBinary: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/mooring")
    }

    static func state(link: URL, target: URL) -> State {
        let fileManager = FileManager.default
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path) else {
            return fileManager.fileExists(atPath: link.path) ? .pointsElsewhere(link.path) : .missing
        }
        let resolved = URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent())
        return resolved.standardizedFileURL.path == target.standardizedFileURL.path ? .installed : .pointsElsewhere(destination)
    }

    /// Links `link` to `target`, creating the folder and replacing a missing or stale link. Throws for a regular file.
    static func install(link: URL, target: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let attributes = try? fileManager.attributesOfItem(atPath: link.path) {
            guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else { throw CLIInstallerError.notALink }
            try fileManager.removeItem(at: link)
        }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
    }
}

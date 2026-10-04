import Foundation

/// The version of the Mooring app this `mooring` binary ships in, which `--version` and the MCP server report.
public enum AppVersion {
    /// The `CFBundleShortVersionString` of the nearest `*.app` that holds `executable` once symlinks are resolved
    /// (`~/.local/bin/mooring` links into `Mooring.app/Contents/Helpers`), or "unknown" outside a bundle.
    public static func current(executable: String) -> String {
        guard let resolved = Doctor.resolvePath(executable) else { return "unknown" }
        var folder = URL(fileURLWithPath: resolved).deletingLastPathComponent()
        while folder.path != "/" {
            if folder.pathExtension == "app" {
                let plist = folder.appendingPathComponent("Contents/Info.plist")
                let info = NSDictionary(contentsOf: plist)
                return info?["CFBundleShortVersionString"] as? String ?? "unknown"
            }
            folder.deleteLastPathComponent()
        }
        return "unknown"
    }
}

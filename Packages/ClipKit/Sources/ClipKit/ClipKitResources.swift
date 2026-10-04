import Foundation
import Logging

/// The one logger Maccy's code uses. Messages carry counts and states only, never item titles or
/// contents; tests swap the handler to check that.
enum ClipKitLog {
    static var logger = Logger(label: "dev.mooring.clipkit")
}

extension Bundle {
    /// ClipKit's resources: Maccy's English strings and sounds.
    static var clipKit: Bundle { .module }
}

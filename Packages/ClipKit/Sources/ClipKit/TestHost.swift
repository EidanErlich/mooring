import Foundation
import MachO

/// Whether this process is running tests: an XCTest host, or Swift Testing / XCTest loaded into it.
/// Stands in for Maccy's `AppDelegate.isTesting` (the `enable-testing` launch argument).
enum TestHost {
    static let isActive: Bool = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }

        let testFrameworks = ["/Testing.framework/", "/XCTest.framework/"]
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index).map({ String(cString: $0) }) else { continue }
            if testFrameworks.contains(where: name.contains) {
                return true
            }
        }
        return false
    }()
}

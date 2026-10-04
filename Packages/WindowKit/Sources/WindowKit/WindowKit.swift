import Foundation
import MachO
import os

/// Mooring's handle on the vendored Loop window manager. Nothing in Loop runs until `start()`.
@MainActor
public final class WindowKit {
    public let capabilities: Capabilities

    /// The instance whose `start()` is in effect. Loop's managers are process-wide, so only one runs.
    private(set) static var runningOwner: ObjectIdentifier?

    public var isRunning: Bool {
        Self.runningOwner == ObjectIdentifier(self)
    }

    /// Creates nothing and changes nothing; the capabilities take effect at `start()`.
    public init(capabilities: Capabilities = .live) {
        self.capabilities = capabilities
    }

    /// Starts Loop's triggers, event taps and drag observers. Calling it again while running does nothing.
    public func start() {
        guard Self.runningOwner == nil else { return }
        Self.runningOwner = ObjectIdentifier(self)

        Capabilities.active = capabilities
        capabilities.logFailures()
        LoopManager.shared.start()
        WindowDragManager.shared.addObservers()
    }

    /// Removes every event tap, observer and multitouch listener `start()` installed, and closes
    /// the radial menu and preview at once. Calling it again, or before `start()`, does nothing.
    public func stop() {
        guard isRunning else { return }
        Self.runningOwner = nil

        LoopManager.shared.shutdown()
        WindowDragManager.shared.shutdown()
    }
}

// MARK: - Singleton tracking

extension WindowKit {
    private nonisolated static let singletonCount = OSAllocatedUnfairLock(initialState: 0)

    /// Debug counter: how many of Loop's `shared` managers this process has created.
    public nonisolated static var instantiatedSingletons: Int {
        singletonCount.withLock { $0 }
    }

    /// Wraps each of Loop's `static let shared = …` initialisers, so creating one is counted.
    nonisolated static func track<Instance: AnyObject>(_ instance: Instance) -> Instance {
        singletonCount.withLock { $0 += 1 }
        return instance
    }
}

extension UserDefaults {
    static let windowKitProductionSuiteName = "dev.mooring.windows"

    /// Under a test host, a scratch suite, so tests never touch the user's real Windows settings.
    static let windowKitSuiteName = TestHost.isActive ? "dev.mooring.windows.tests" : windowKitProductionSuiteName

    /// Loop's settings live here, apart from Mooring's own `UserDefaults.standard`, and never sync to iCloud.
    static let windowKit = UserDefaults(suiteName: windowKitSuiteName)!
}

/// Whether this process is running tests: an XCTest host, or Swift Testing / XCTest loaded into it.
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

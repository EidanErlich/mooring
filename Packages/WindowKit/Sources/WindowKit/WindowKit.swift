import Foundation
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

    public init(capabilities: Capabilities = .live) {
        self.capabilities = capabilities
        Capabilities.active = capabilities
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
    /// Loop's settings live here, apart from Mooring's own `UserDefaults.standard`, and never sync to iCloud.
    static let windowKit = UserDefaults(suiteName: "dev.mooring.windows")!
}

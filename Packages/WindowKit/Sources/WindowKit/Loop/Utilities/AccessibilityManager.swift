// Adapted from Loop@0ac6d83: Loop/Utilities/AccessibilityManager.swift
//
//  AccessibilityManager.swift
//  Loop
//
//  Created by Kai Azim on 2023-04-08.
//

import Defaults
import SwiftUI

/// Stores and manages the accessibility permission state for Loop.
@MainActor
final class AccessibilityManager {
    static let shared: AccessibilityManager = WindowKit.track(.init())

    private var permissionCheckerTask: Task<(), Never>!

    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private(set) var isGranted: Bool

    private init() {
        self.isGranted = Self.getStatus()

        // Setup permission change notification monitoring
        self.permissionCheckerTask = Task {
            let notifications = DistributedNotificationCenter
                .default()
                .notifications(named: .AXPermissionsChanged)

            for await _ in notifications {
                // It seems like the notification is sent immediately after a state change, sometimes before the actual
                // reading from `AXIsProcessTrustedWithOptions` is updated.
                // So sleep for 250 milliseconds (this is generous, but just to ensure that the reading will be correct).
                try? await Task.sleep(for: .milliseconds(250))

                let status = Self.getStatus()
                self.yield(status)
            }
        }
    }

    deinit {
        permissionCheckerTask.cancel()

        let currentContinuations = Array(continuations.values)
        continuations.removeAll()

        for continuation in currentContinuations {
            continuation.finish()
        }
    }

    /// Mooring: how many streams are open, so tests can see that `start()` installs one set of observers.
    var activeStreamCount: Int {
        continuations.count
    }

    // MARK: Streaming

    /// Stream new changes to Loop's accessibility permissions.
    /// - Parameter initial: whether to send an initial value corresponding to Loop's current permissions
    /// - Returns: an AsyncStream.
    func stream(initial: Bool = true) -> AsyncStream<Bool> {
        AsyncStream<Bool> { continuation in
            let id = UUID()
            continuations[id] = continuation

            if initial {
                continuation.yield(isGranted)
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }

                Task { @MainActor in
                    self.continuations[id] = nil
                }
            }
        }
    }

    /// This will yield a new value to all streams if the provided value differs from the previous value.
    /// - Parameter value: the provided value.
    @MainActor
    private func yield(_ value: Bool) {
        guard value != isGranted else { return }

        let currentContinuations = continuations.values

        for continuation in currentContinuations {
            continuation.yield(value)
        }

        isGranted = value
    }

    // MARK: Permissions Checking

    /// Determines if the app has accessibility permissions.
    /// - Returns: whether the app has accessibility permissions.
    private static func getStatus() -> Bool {
        AXIsProcessTrusted()
    }
}

private extension Notification.Name {
    /// Not publicly documented, but gets sent when ANY application's AX API permission change.
    /// From `HIServices.framework`
    static let AXPermissionsChanged = Notification.Name(rawValue: "com.apple.accessibility.api")
}

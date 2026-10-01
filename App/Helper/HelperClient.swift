// Adapted from Awayke@b502251: Awayke/HelperManager.swift
//
//  HelperManager.swift
//  Awayke
//

import Foundation
import os
import ServiceManagement

/// Where the privileged helper stands with launchd and the user's approval.
enum HelperStatus: Equatable {
    case notRegistered
    case requiresApproval
    case enabled
    case notFound

    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .requiresApproval: self = .requiresApproval
        case .enabled: self = .enabled
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }
}

enum HelperClientError: LocalizedError {
    case notApproved
    case connection(String)
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .notApproved:
            return "Mooring's helper isn't enabled. Approve it in System Settings → General → Login Items & Extensions."
        case .connection(let detail):
            return "Couldn't connect to Mooring's helper: \(detail)"
        case .remote(let detail):
            return detail
        }
    }
}

/// The app's side of the privileged helper: registration with SMAppService and
/// the XPC calls. The only path from the app to `pmset`.
@MainActor
final class HelperClient {
    static let shared = HelperClient()
    static let callTimeout: TimeInterval = 10

    private let service = SMAppService.daemon(plistName: MooringHelperConstants.launchdPlistName)
    private let log = Logger(subsystem: "dev.mooring", category: "helper")
    private var connection: NSXPCConnection?

    private init() {}

    var status: HelperStatus { HelperStatus(service.status) }

    /// Idempotent. On a fresh install macOS asks the user to approve the helper
    /// in System Settings; that pending approval is not an error.
    func register() throws {
        do {
            try service.register()
        } catch {
            if status == .requiresApproval {
                log.notice("helper registered, waiting for approval")
                return
            }
            log.error("SMAppService.register() failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Unregisters the helper; `LidController.uninstall()` restores lid sleep first.
    func unregister() async throws {
        try await service.unregister()
        connection?.invalidate()
        connection = nil
        log.notice("helper uninstalled")
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func setLidSleepDisabled(_ disabled: Bool) async throws {
        try await call { (helper, finish: @escaping @Sendable (Result<Void, Error>) -> Void) in
            helper.setLidSleepDisabled(disabled) { error in
                finish(error.map { .failure(HelperClientError.remote($0.localizedDescription)) } ?? .success(()))
            }
        }
    }

    func lidSleepDisabled() async throws -> Bool {
        try await call { (helper, finish: @escaping @Sendable (Result<Bool, Error>) -> Void) in
            helper.lidSleepDisabled { value, error in
                finish(error.map { .failure(HelperClientError.remote($0.localizedDescription)) } ?? .success(value))
            }
        }
    }

    /// Keeps the helper's watchdog from restoring sleep; replies with the current SleepDisabled.
    func heartbeat() async throws -> Bool {
        try await call { (helper, finish: @escaping @Sendable (Result<Bool, Error>) -> Void) in
            helper.heartbeat { finish(.success($0)) }
        }
    }

    func version() async throws -> String {
        try await call { (helper, finish: @escaping @Sendable (Result<String, Error>) -> Void) in
            helper.version { finish(.success($0)) }
        }
    }

    /// One XPC call. It can end through the reply, the proxy's error handler or
    /// the 10 s timeout, so the continuation is guarded to resume exactly once.
    private func call<T: Sendable>(
        _ body: @escaping (MooringHelperProtocol, @escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        guard status == .enabled else { throw HelperClientError.notApproved }
        let conn = connection ?? makeConnection()
        connection = conn

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Result<T, Error>) -> Void = { result in
                let isFirst = resumed.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if isFirst { continuation.resume(with: result) }
            }
            Task {
                try? await Task.sleep(for: .seconds(Self.callTimeout))
                finish(.failure(HelperClientError.connection("timed out")))
            }
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                finish(.failure(HelperClientError.connection(error.localizedDescription)))
            }
            guard let helper = proxy as? MooringHelperProtocol else {
                finish(.failure(HelperClientError.connection("proxy is not a MooringHelperProtocol")))
                return
            }
            body(helper, finish)
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: MooringHelperConstants.machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: MooringHelperProtocol.self)
        // Only forget this connection, never a newer one. An interrupted
        // connection is still usable (NSXPC re-establishes it), so it is kept:
        // the helper's watchdog keys off the connection, and churn would make
        // it see the app as gone.
        let identity = ObjectIdentifier(conn)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, let current = self.connection, ObjectIdentifier(current) == identity else { return }
                self.connection = nil
            }
        }
        conn.interruptionHandler = { [log] in
            log.notice("helper connection interrupted; keeping it")
        }
        conn.resume()
        return conn
    }
}

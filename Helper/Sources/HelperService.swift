// Adapted from Awayke@b502251: AwaykeHelper/main.swift
//
//  HelperService.swift
//  MooringHelper
//
//  Privileged launchd daemon installed via SMAppService. Which clients may
//  connect is enforced by the listener's code-signing requirement (main.swift);
//  this type only refuses everyone when no requirement could be loaded. Its
//  watchdog restores sleep when the app disappears.
//

import Foundation
import os

// Mutable state (the watchdog and its timer) is confined to `queue`, and every
// pmset write runs there too, so a watchdog restore never races a client request.
final class HelperService: NSObject, NSXPCListenerDelegate, MooringHelperProtocol, @unchecked Sendable {
    private let clientRequirement: String?
    private let log = Logger(subsystem: "dev.mooring", category: "helper")
    private let queue = DispatchQueue(label: "dev.mooring.helper.watchdog")
    private var watchdog = Watchdog()
    private var timer: DispatchSourceTimer?
    private var termination: DispatchSourceSignal?
    /// Root-owned record that the helper set SleepDisabled, so ownership survives a reboot or crash.
    private let marker = URL(fileURLWithPath: "/Library/Application Support/Mooring/helper-owns-sleep")

    init(clientRequirement: String?) {
        self.clientRequirement = clientRequirement
        super.init()
        let owning = FileManager.default.fileExists(atPath: marker.path) && (try? readSleepDisabled()) == true
        watchdog.didStart(owningSleep: owning, at: Date())
        // launchd sends SIGTERM on unregister, logout, kickstart -k and shutdown.
        signal(SIGTERM, SIG_IGN)
        termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        termination?.setEventHandler { [weak self] in
            if self?.watchdog.sleepDisabledByUs == true { self?.restore(reason: "the helper is being stopped") }
            exit(0)
        }
        termination?.resume()
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + Watchdog.checkInterval, repeating: Watchdog.checkInterval)
        timer?.setEventHandler { [weak self] in self?.checkWatchdog() }
        timer?.resume()
    }

    private func checkWatchdog() {
        guard watchdog.shouldRestore(at: Date()) else { return }
        restore(reason: "the app disconnected or stopped sending heartbeats")
    }

    private func restore(reason: String) {
        do {
            _ = try PMSet.run(PMSet.disableSleepArguments(false))
            watchdog.didRestore()
            recordOwnership(false)
            log.notice("watchdog restored sleep: \(reason, privacy: .public)")
        } catch {
            log.error("watchdog restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordOwnership(_ owned: Bool) {
        if owned {
            try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: marker.path, contents: nil)
        } else {
            try? FileManager.default.removeItem(at: marker)
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard clientRequirement != nil else {
            log.error("refusing connection: helper built without a signing certificate")
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: MooringHelperProtocol.self)
        connection.exportedObject = self
        queue.sync { watchdog.connectionOpened() }
        connection.invalidationHandler = { [weak self] in
            self?.queue.async { self?.watchdog.connectionClosed(at: Date()) }
        }
        connection.resume()
        return true
    }

    func setLidSleepDisabled(_ disabled: Bool, reply: @escaping @Sendable (NSError?) -> Void) {
        queue.async { self.setOnQueue(disabled, reply: reply) }
    }

    private func setOnQueue(_ disabled: Bool, reply: @escaping @Sendable (NSError?) -> Void) {
        do {
            _ = try PMSet.run(PMSet.disableSleepArguments(disabled))
            watchdog.didSetSleepDisabled(disabled, at: Date())
            recordOwnership(disabled)
            log.notice("disablesleep set to \(disabled ? 1 : 0, privacy: .public)")
            reply(nil)
        } catch {
            log.error("disablesleep \(disabled ? 1 : 0, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            reply(error as NSError)
        }
    }

    private func readSleepDisabled() throws -> Bool {
        guard let value = PMSet.sleepDisabled(inOutput: try PMSet.run(PMSet.readArguments)) else {
            throw PMSetError(status: 0, message: "SleepDisabled not found in pmset -g output")
        }
        return value
    }

    func lidSleepDisabled(reply: @escaping @Sendable (Bool, NSError?) -> Void) {
        do {
            reply(try readSleepDisabled(), nil)
        } catch {
            log.error("reading SleepDisabled failed: \(error.localizedDescription, privacy: .public)")
            reply(false, error as NSError)
        }
    }

    func heartbeat(reply: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            let sleepDisabled = (try? self.readSleepDisabled()) ?? false
            self.watchdog.didHeartbeat(at: Date(), sleepDisabled: sleepDisabled)
            if sleepDisabled { self.recordOwnership(true) }
            reply(sleepDisabled)
        }
    }

    func version(reply: @escaping @Sendable (String) -> Void) {
        reply(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
    }
}

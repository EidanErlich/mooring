// Adapted from Awayke@b502251: AwaykeHelper/main.swift
//
//  HelperService.swift
//  MooringHelper
//
//  Privileged launchd daemon installed via SMAppService. Which clients may
//  connect is enforced by the listener's code-signing requirement (main.swift);
//  this type only refuses everyone when no requirement could be loaded.
//

import Foundation
import os

final class HelperService: NSObject, NSXPCListenerDelegate, MooringHelperProtocol, Sendable {
    private let clientRequirement: String?
    private let log = Logger(subsystem: "dev.mooring", category: "helper")

    init(clientRequirement: String?) {
        self.clientRequirement = clientRequirement
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard clientRequirement != nil else {
            log.error("refusing connection: helper built without a signing certificate")
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: MooringHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func setLidSleepDisabled(_ disabled: Bool, reply: @escaping @Sendable (NSError?) -> Void) {
        do {
            _ = try PMSet.run(PMSet.disableSleepArguments(disabled))
            log.notice("disablesleep set to \(disabled ? 1 : 0, privacy: .public)")
            reply(nil)
        } catch {
            log.error("disablesleep \(disabled ? 1 : 0, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            reply(error as NSError)
        }
    }

    func lidSleepDisabled(reply: @escaping @Sendable (Bool, NSError?) -> Void) {
        do {
            let output = try PMSet.run(PMSet.readArguments)
            guard let value = PMSet.sleepDisabled(inOutput: output) else {
                throw PMSetError(status: 0, message: "SleepDisabled not found in pmset -g output")
            }
            reply(value, nil)
        } catch {
            log.error("reading SleepDisabled failed: \(error.localizedDescription, privacy: .public)")
            reply(false, error as NSError)
        }
    }

    func version(reply: @escaping @Sendable (String) -> Void) {
        reply(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
    }
}

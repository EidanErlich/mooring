// Adapted from Awayke@b502251: AwaykeHelper/AwaykeHelperProtocol.swift
//
//  MooringHelperProtocol.swift
//
//  The privileged helper's whole XPC surface (docs/SPEC.md 1.5). Compiled into
//  both the app and the helper.
//

import Foundation

@objc protocol MooringHelperProtocol {
    /// Runs `pmset -a disablesleep 1` or `0`.
    func setLidSleepDisabled(_ disabled: Bool, reply: @escaping @Sendable (NSError?) -> Void)
    /// Reads `SleepDisabled` from `pmset -g`. On failure the Bool is false and the error is set.
    func lidSleepDisabled(reply: @escaping @Sendable (Bool, NSError?) -> Void)
    func version(reply: @escaping @Sendable (String) -> Void)
}

enum MooringHelperConstants {
    static let machServiceName = "dev.mooring.helper"
    static let launchdPlistName = "dev.mooring.helper.plist"
}

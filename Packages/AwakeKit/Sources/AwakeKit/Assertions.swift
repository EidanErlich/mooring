// Adapted from Awayke@b502251: Awayke/DisplayWakeKeeper.swift
//
//  DisplayWakeKeeper.swift
//  Awayke
//
//  Holds an IOPMAssertion that prevents display sleep, screen saver,
//  and auto-lock while Awayke is active. Same mechanism as
//  `caffeinate -d`. Released automatically if the app exits.
//

import IOKit.pwr_mgt
import os

/// Makes the two IOKit power assertions match what the engine wants.
@MainActor
public protocol AssertionApplying: AnyObject {
    func apply(system: Bool, display: Bool)
}

/// The real assertions: idle system sleep and idle display sleep, both named
/// "Mooring" so they show up by name in `pmset -g assertions`. The kernel
/// releases them if the process dies.
@MainActor
public final class IOPMAssertions: AssertionApplying {
    public nonisolated static let assertionName = "Mooring"

    private var systemID: IOPMAssertionID?
    private var displayID: IOPMAssertionID?
    private let log = Logger(subsystem: "dev.mooring", category: "engine")

    public init() {}

    public func apply(system: Bool, display: Bool) {
        set(&systemID, wanted: system, type: kIOPMAssertPreventUserIdleSystemSleep)
        set(&displayID, wanted: display, type: kIOPMAssertPreventUserIdleDisplaySleep)
    }

    private func set(_ id: inout IOPMAssertionID?, wanted: Bool, type: String) {
        switch (wanted, id) {
        case (true, nil):
            var newID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), Self.assertionName as CFString, &newID
            )
            if result == kIOReturnSuccess {
                id = newID
            } else {
                log.error("creating \(type, privacy: .public) failed: \(result, privacy: .public)")
            }
        case (false, let held?):
            IOPMAssertionRelease(held)
            id = nil
        default:
            break
        }
    }
}

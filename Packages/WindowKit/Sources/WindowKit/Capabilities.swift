import Darwin
import Foundation
import os

/// Which private-API features this macOS still provides. Every private symbol Loop uses is looked up
/// here; a missing symbol turns its feature off and hides the actions that depend on it.
public struct Capabilities: Sendable, Equatable {
    /// `_AXUIElementGetWindow` plus SkyLight's window query, without which no window can be resolved.
    public let windowIDLookup: Bool
    /// SkyLight's bridged operations that move windows between Mission Control spaces.
    public let skyLightMoves: Bool
    /// Bringing a stashed window's process and window to the front.
    public let stash: Bool
    /// Focusing another window (the focus actions).
    public let windowFocus: Bool

    static let windowIDSymbols = [
        "_AXUIElementGetWindow",
        "SLSMainConnectionID",
        "SLSWindowQueryWindows",
        "SLSWindowQueryResultCopyWindows",
        "SLSWindowIteratorAdvance",
        "SLSWindowIteratorGetWindowID",
        "SLSWindowIteratorGetParentID",
        "SLSWindowIteratorGetTags"
    ]

    static let spaceMoveSymbols = [
        "objc_msgSend",
        "OBJC_CLASS_$_SLSBridgedMoveWindowsToManagedSpaceOperation",
        "OBJC_CLASS_$_SLSBridgedCopyManagedDisplaySpacesOperation",
        "OBJC_CLASS_$_SLSBridgedCopySpacesForWindowsOperation"
    ]

    static let frontProcessSymbols = [
        "GetProcessForPID",
        "_SLPSSetFrontProcessWithOptions",
        "SLPSPostEventRecordTo"
    ]

    public static let live = Capabilities(loadSymbol: Capabilities.liveSymbol)

    public init(loadSymbol: (String) -> UnsafeMutableRawPointer?) {
        func all(_ names: [String]) -> Bool {
            names.allSatisfy { loadSymbol($0) != nil }
        }

        windowIDLookup = all(Self.windowIDSymbols)
        skyLightMoves = all(Self.spaceMoveSymbols)
        stash = all(Self.frontProcessSymbols)
        windowFocus = all(Self.frontProcessSymbols)
    }

    /// Action ids whose feature failed. Without window id lookup no action can find its window.
    public var hidden: Set<String> {
        var directions: [WindowDirection] = []
        if !windowIDLookup {
            directions += WindowDirection.allCases
        }
        if !skyLightMoves {
            directions += WindowDirection.spaceSwitching
        }
        if !stash {
            directions += [.stash, .unstash]
        }
        if !windowFocus {
            directions += WindowDirection.focus
        }
        return Set(directions.filter(\.isMenuAction).map(\.rawValue))
    }

    var failedFeatures: [String] {
        [
            ("window id lookup", windowIDLookup),
            ("SkyLight moves", skyLightMoves),
            ("stash", stash),
            ("window focus", windowFocus)
        ]
        .filter { !$0.1 }
        .map(\.0)
    }
}

// MARK: - Symbol lookup

extension Capabilities {
    private static let skyLightHandle = SymbolHandle(dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY))
    private static let processHandle = SymbolHandle(dlopen(nil, RTLD_LAZY))

    /// Looks a symbol up in SkyLight, then in everything already loaded.
    static func liveSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        if let pointer = skyLightHandle.pointer, let symbol = dlsym(pointer, name) {
            return symbol
        }
        guard let pointer = processHandle.pointer else { return nil }
        return dlsym(pointer, name)
    }

    /// A `dlopen` handle, which stays valid for the life of the process.
    private struct SymbolHandle: @unchecked Sendable {
        let pointer: UnsafeMutableRawPointer?

        init(_ pointer: UnsafeMutableRawPointer?) {
            self.pointer = pointer
        }
    }
}

// MARK: - The capabilities in effect

extension Capabilities {
    private static let activeState = OSAllocatedUnfairLock<Capabilities?>(initialState: nil)
    private static let loggedFailures = OSAllocatedUnfairLock<Set<String>>(initialState: [])
    private static let logger = Logger(subsystem: "dev.mooring", category: "windows")

    /// The capabilities Loop's private-API call sites check: the last `WindowKit`'s, or `.live`.
    static var active: Capabilities {
        get { activeState.withLock { $0 } ?? .live }
        set { activeState.withLock { $0 = newValue } }
    }

    /// Logs each failed feature once per process.
    func logFailures() {
        for feature in failedFeatures {
            let isNew = Self.loggedFailures.withLock { $0.insert(feature).inserted }
            if isNew {
                Self.logger.error("Windows: \(feature, privacy: .public) is unavailable on this macOS; its actions are hidden")
            }
        }
    }
}

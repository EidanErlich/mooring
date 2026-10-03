// Adapted from Loop@0ac6d83: Loop/Private APIs/PrivateApis.swift
//
//  PrivateApis.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-27.
//
// This file declares private API functions using `@_silgen_name`.
//
// NOTE:
// `@_silgen_name` directly binds these Swift declarations to linker symbols.
// This is convenient, but unsafe: if the symbol is missing on a given macOS
// version, the process will crash at load time.
//
// For most private APIs, prefer using a dynamic "symbol loader" (see
// SkyLightSymbolLoader) where functions are resolved at runtime and stored
// as optional pointers. This allows graceful fallback on systems where the
// symbols are unavailable, instead of crashing.

import Cocoa

// Mooring: these were `@_silgen_name` bindings, which stop the whole app launching if a symbol
// disappears. They now resolve through `Capabilities` at first use and fail closed instead.

private typealias GetProcessForPIDFunc = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
private let getProcessForPIDSymbol: GetProcessForPIDFunc? = Capabilities.liveSymbol("GetProcessForPID")
    .map { unsafeBitCast($0, to: GetProcessForPIDFunc.self) }

func GetProcessForPID(
    _ pid: pid_t,
    _ psn: inout ProcessSerialNumber
) -> OSStatus {
    guard let getProcessForPIDSymbol else { return OSStatus(procNotFound) }
    return getProcessForPIDSymbol(pid, &psn)
}

private typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private let axUIElementGetWindowSymbol: AXUIElementGetWindowFunc? = Capabilities.liveSymbol("_AXUIElementGetWindow")
    .map { unsafeBitCast($0, to: AXUIElementGetWindowFunc.self) }

func AXUIElementGetWindow(
    _ axUiElement: AXUIElement,
    _ wid: inout CGWindowID
) -> AXError {
    guard let axUIElementGetWindowSymbol else { return .apiDisabled }
    return axUIElementGetWindowSymbol(axUiElement, &wid)
}

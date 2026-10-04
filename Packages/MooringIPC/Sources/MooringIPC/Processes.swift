import Darwin
import Foundation

public struct ProcessEntry: Sendable, Equatable {
    public var pid: Int32
    public var parent: Int32
    public var name: String

    public init(pid: Int32, parent: Int32, name: String) {
        self.pid = pid
        self.parent = parent
        self.name = name
    }
}

/// Looks processes up by pid.
public protocol ProcessTable: Sendable {
    func entry(_ pid: Int32) -> ProcessEntry?
    /// The process's command line (`argv`, the program first), or nil when it can't be read.
    func arguments(_ pid: Int32) -> [String]?
}

/// The real process table, read with `sysctl`.
public struct SystemProcessTable: ProcessTable {
    public init() {}

    public func entry(_ pid: Int32) -> ProcessEntry? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        // A pid that doesn't exist succeeds with a size of 0.
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
            String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
        return ProcessEntry(pid: pid, parent: info.kp_eproc.e_ppid, name: name)
    }

    /// Read with `KERN_PROCARGS2`, which only works for the caller's own user's processes.
    public func arguments(_ pid: Int32) -> [String]? {
        var argmaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argmax: Int32 = 0
        var argmaxSize = MemoryLayout<Int32>.size
        guard sysctl(&argmaxMib, UInt32(argmaxMib.count), &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var buffer = [UInt8](repeating: 0, count: Int(argmax))
        var size = buffer.count
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return Self.parseArguments(Array(buffer.prefix(size)))
    }

    /// The `argv` in a `KERN_PROCARGS2` buffer: an `Int32` argc, the executable path and its NUL, NUL padding, then argc
    /// NUL-terminated strings (the environment follows). Nil when the buffer is too short or has no executable path; an
    /// argument cut off by the end of the buffer ends the list.
    static func parseArguments(_ buffer: [UInt8]) -> [String]? {
        let countSize = MemoryLayout<Int32>.size
        guard buffer.count >= countSize else { return nil }
        let argc = buffer.prefix(countSize).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0, let pathEnd = buffer[countSize...].firstIndex(of: 0) else { return nil }
        var index = pathEnd
        while index < buffer.count, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < buffer.count, let end = buffer[index...].firstIndex(of: 0) {
            // An argument that isn't UTF-8 keeps its place as an empty string.
            arguments.append(String(bytes: buffer[index..<end], encoding: .utf8) ?? "")
            index = end + 1
        }
        return arguments
    }
}

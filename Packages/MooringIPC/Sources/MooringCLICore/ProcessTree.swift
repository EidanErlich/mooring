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
}

public enum ProcessTree {
    /// Ancestors `--watch-pid auto` looks past: shells and the wrappers that sit between a shell and its parent.
    static let skipped: Set<String> = [
        "sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "csh", "login", "sudo", "env", "nohup", "mooring"
    ]

    /// The first process at or above `pid` that isn't a shell or wrapper, or nil when the walk reaches pid 1 or 0 first.
    public static func autoWatch(from pid: Int32, in table: some ProcessTable) -> ProcessEntry? {
        var current = pid
        // The cap guards against a table that loops.
        for _ in 0..<64 {
            guard current > 1, let entry = table.entry(current) else { return nil }
            if !skipped.contains(normalized(entry.name)) { return entry }
            current = entry.parent
        }
        return nil
    }

    /// The owner name for a watched process: `claude` is "Claude Code", `codex` is "Codex", anything else keeps its name.
    public static func agentName(for processName: String) -> String {
        switch normalized(processName) {
        case "claude": "Claude Code"
        case "codex": "Codex"
        default: processName
        }
    }

    /// Lowercased, without the leading `-` that marks a login shell.
    private static func normalized(_ name: String) -> String {
        name.drop { $0 == "-" }.lowercased()
    }
}

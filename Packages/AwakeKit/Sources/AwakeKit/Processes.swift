import Darwin
import Foundation

/// A running exit watch; cancel it when the lease it serves ends.
@MainActor
public protocol ProcessWatch: AnyObject {
    func cancel()
}

/// What the engine needs to know about other processes.
@MainActor
public protocol ProcessInspecting: AnyObject {
    /// When the process started, or nil if there is no such process.
    func startTime(of pid: Int32) -> Date?
    /// Calls `onExit` on the main actor once, when the process exits.
    func watchExit(of pid: Int32, onExit: @escaping @MainActor () -> Void) -> any ProcessWatch
}

@MainActor
public final class SystemProcesses: ProcessInspecting {
    public init() {}

    public func startTime(of pid: Int32) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000)
    }

    public func watchExit(of pid: Int32, onExit: @escaping @MainActor () -> Void) -> any ProcessWatch {
        DispatchProcessWatch(pid: pid, onExit: onExit)
    }
}

@MainActor
private final class DispatchProcessWatch: ProcessWatch {
    private let source: any DispatchSourceProcess

    init(pid: Int32, onExit: @escaping @MainActor () -> Void) {
        source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [source] in
            source.cancel()
            MainActor.assumeIsolated { onExit() }
        }
        source.resume()
    }

    func cancel() {
        source.cancel()
    }
}

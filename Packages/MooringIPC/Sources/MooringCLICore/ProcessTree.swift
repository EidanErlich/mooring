import MooringIPC

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
            if !skipped.contains(AgentDetection.normalized(entry.name)) { return entry }
            current = entry.parent
        }
        return nil
    }

    /// The owner name for a watched process: a known agent gets its display name, anything else keeps its name.
    public static func agentName(for processName: String) -> String {
        AgentDetection.agents[AgentDetection.normalized(processName)] ?? processName
    }
}

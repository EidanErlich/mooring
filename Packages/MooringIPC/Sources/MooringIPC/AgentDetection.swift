/// Tells agent callers from people by walking the caller's process ancestry.
///
/// Names match the agent CLIs exactly, case included, so the Claude and Codex desktop apps (`Claude`, `Codex`) and
/// the terminals inside them count as people. The trade-off: a process a desktop app launches directly (an MCP
/// server Claude.app starts, say) counts as a person too, unless it runs under one of the CLIs.
public enum AgentDetection {
    /// Process names of the agent CLIs, exactly as they run, and the name shown for each.
    public static let agents: [String: String] = [
        "claude": "Claude Code", "codex": "Codex", "cursor-agent": "Cursor Agent",
        "gemini": "Gemini CLI", "aider": "Aider", "opencode": "OpenCode"
    ]

    /// The display name of the first known agent at or above `pid`, or nil for a person.
    /// The walk stops at pid 1 or 0, at a pid missing from the table, and after 64 steps.
    public static func agent(for pid: Int32, in table: some ProcessTable) -> String? {
        var current = pid
        // The cap guards against a table that loops.
        for _ in 0..<64 {
            guard current > 1, let entry = table.entry(current) else { return nil }
            if let name = agents[normalized(entry.name)] { return name }
            current = entry.parent
        }
        return nil
    }

    /// Without the leading `-` that marks a login shell; case is kept.
    public static func normalized(_ name: String) -> String {
        String(name.drop { $0 == "-" })
    }
}

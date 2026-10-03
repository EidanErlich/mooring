import Foundation

/// How an MCP client's self-reported name shows in lease owners and notifications.
public enum MCPClientName {
    /// The name a person at the keyboard goes by, which a client may not take.
    public static let personName = "Terminal"

    private static let known = ["claude-ai": "Claude Desktop", "cursor-vscode": "Cursor"]
    private static let displayLimit = 40
    private static let slugLimit = 24

    /// The name to show: a friendly name for known clients, otherwise the reported one with control
    /// characters dropped, cut to 40 characters and trimmed. "MCP client" when nothing usable is left, or when what is
    /// left would pass for a person ("Terminal", in any case).
    public static func display(_ raw: String?) -> String {
        guard let raw else { return "MCP client" }
        if let name = known[raw] { return name }
        let visible = String(String.UnicodeScalarView(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        let cleaned = String(visible.trimmingCharacters(in: .whitespacesAndNewlines).prefix(displayLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.caseInsensitiveCompare(personName) != .orderedSame else { return "MCP client" }
        return cleaned
    }

    /// A lowercase id fragment: runs of non-alphanumerics become one "-", no leading or trailing "-",
    /// at most 24 characters. "client" when nothing is left.
    public static func slug(_ display: String) -> String {
        var result = ""
        var pendingDash = false
        for character in display.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                if pendingDash, !result.isEmpty { result.append("-") }
                pendingDash = false
                result.append(character)
            } else {
                pendingDash = true
            }
        }
        var cut = String(result.prefix(slugLimit))
        while cut.hasSuffix("-") { cut.removeLast() }
        return cut.isEmpty ? "client" : cut
    }
}

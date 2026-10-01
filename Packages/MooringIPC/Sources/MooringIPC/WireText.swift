/// Text conventions the CLI shares with the app: duration and level grammar, level names and exit codes.
public enum WireText {
    /// Exit code when the app's socket can't be reached.
    public static let unreachableExitCode: Int32 = 3

    /// Seconds for `<n>h<n>m<n>s` groups (each unit at most once, in that order), or nil when malformed or zero.
    public static func parseDuration(_ text: String) -> Double? {
        let units: [(letter: UInt8, seconds: Int)] = [
            (UInt8(ascii: "h"), 3600), (UInt8(ascii: "m"), 60), (UInt8(ascii: "s"), 1)
        ]
        var total = 0
        var nextUnit = 0
        var digits = ""
        var sawGroup = false
        for byte in text.utf8 {
            if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
                digits.append(Character(UnicodeScalar(byte)))
                continue
            }
            guard let unit = units[nextUnit...].firstIndex(where: { $0.letter == byte }),
                  let count = Int(digits), count > 0 else { return nil }
            let (product, productOverflow) = count.multipliedReportingOverflow(by: units[unit].seconds)
            let (sum, sumOverflow) = total.addingReportingOverflow(product)
            guard !productOverflow, !sumOverflow else { return nil }
            total = sum
            nextUnit = unit + 1
            digits = ""
            sawGroup = true
        }
        guard digits.isEmpty, sawGroup, total > 0 else { return nil }
        return Double(total)
    }

    /// `(display, lid)` flags for `system`, `display`, `lid`, `display,lid` or `lid,display`; nil otherwise.
    public static func parseLevel(_ text: String) -> (display: Bool, lid: Bool)? {
        switch text {
        case "system": (false, false)
        case "display": (true, false)
        case "lid": (false, true)
        case "display,lid", "lid,display": (true, true)
        default: nil
        }
    }

    /// The canonical level name for a pair of flags (the inverse of `parseLevel`).
    public static func levelName(display: Bool, lid: Bool) -> String {
        switch (display, lid) {
        case (false, false): "system"
        case (true, false): "display"
        case (false, true): "lid"
        case (true, true): "display,lid"
        }
    }

    /// The CLI's exit status for an error the app returned.
    public static func exitCode(for code: ErrorCode) -> Int32 {
        switch code {
        case .badRequest, .notFound: 1
        case .guardrail, .denied: 2
        case .internal: 4
        }
    }
}

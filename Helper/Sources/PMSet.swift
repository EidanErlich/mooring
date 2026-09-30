import Foundation

/// The only way anything in Mooring touches `pmset`. Arguments are fixed arrays;
/// nothing a client sends reaches `Process`.
enum PMSet {
    static let executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    static let readArguments = ["-g"]

    static func disableSleepArguments(_ disabled: Bool) -> [String] {
        ["-a", "disablesleep", disabled ? "1" : "0"]
    }

    /// Parses the `SleepDisabled` line of `pmset -g`. Returns nil when the line
    /// is missing or its value isn't exactly 0 or 1.
    static func sleepDisabled(inOutput output: String) -> Bool? {
        guard let line = output.split(separator: "\n").first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("SleepDisabled")
        }) else { return nil }
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2 else { return nil }
        switch fields[1] {
        case "0": return false
        case "1": return true
        default: return nil
        }
    }

    /// Runs pmset and returns stdout; throws `PMSetError` on a non-zero exit.
    static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw PMSetError(status: process.terminationStatus, message: message.isEmpty ? "pmset failed" : message)
        }
        return String(data: output, encoding: .utf8) ?? ""
    }
}

struct PMSetError: Error, CustomNSError {
    let status: Int32
    let message: String

    static var errorDomain: String { "dev.mooring.helper" }
    var errorCode: Int { Int(status) }
    var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: message] }
}

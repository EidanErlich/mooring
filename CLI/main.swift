import Darwin
import Foundation
import MooringCLICore
import MooringIPC

/// The absolute, symlink-free path of this executable, for doctor's PATH check.
func ownExecutablePath() -> String {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    if _NSGetExecutablePath(&buffer, &size) == 0, let resolved = realpath(buffer, nil) {
        defer { free(resolved) }
        return String(cString: resolved)
    }
    return Bundle.main.executablePath ?? ""
}

/// Writes to a standard stream and flushes, so output is complete before we exit.
func writer(to handle: FileHandle) -> @Sendable (String) -> Void {
    { text in handle.write(Data(text.utf8)) }
}

/// Reads at most `limit` bytes from stdin, stopping early at end of input.
func readStandardInput(limit: Int) -> Data {
    var data = Data()
    var chunk = [UInt8](repeating: 0, count: 65_536)
    while data.count < limit {
        let count = read(STDIN_FILENO, &chunk, min(chunk.count, limit - data.count))
        if count < 0, errno == EINTR { continue }
        guard count > 0 else { break }
        data.append(contentsOf: chunk[..<count])
    }
    return data
}

let executablePath = ownExecutablePath()
let environment = CLIEnvironment(
    client: SocketClient(path: SocketClient.defaultPath),
    processes: SystemProcessTable(),
    ownPID: getpid(),
    parentPID: getppid(),
    write: writer(to: .standardOutput),
    writeError: writer(to: .standardError),
    newID: { UUID().uuidString },
    now: { Date() },
    ownBinaryPath: executablePath,
    pathEnv: ProcessInfo.processInfo.environment["PATH"],
    home: FileManager.default.homeDirectoryForCurrentUser,
    readInput: readStandardInput(limit:),
    hookClient: SocketClient(path: SocketClient.defaultPath, replyTimeout: 1.5, launchWait: 0, launcher: {}),
    lidClient: SocketClient(path: SocketClient.defaultPath, replyTimeout: 65),
    windowClient: SocketClient(path: SocketClient.defaultPath, replyTimeout: 120),
    claude: { probeClaude(pathEnv: ProcessInfo.processInfo.environment["PATH"]) },
    // `mooring mcp` calls this from a background queue, never the main thread.
    readLine: { Swift.readLine(strippingNewline: true) },
    appVersion: AppVersion.current(executable: executablePath)
)

let arguments = Array(CommandLine.arguments.dropFirst())
let code = await MooringCLI.run(arguments, environment: environment)

// `anchor` reports a child killed by HUP, INT or TERM as 128 + signal. Die by the same signal,
// so a shell loop around `mooring anchor` stops on Ctrl-C instead of carrying on.
if arguments.first == "anchor", [129, 130, 143].contains(code) {
    let signalNumber = code - 128
    signal(signalNumber, SIG_DFL)
    kill(getpid(), signalNumber)
}
exit(code)

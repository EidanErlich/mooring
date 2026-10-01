import Darwin
import Foundation
import MooringCLICore

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

let environment = CLIEnvironment(
    client: SocketClient(path: SocketClient.defaultPath),
    processes: SystemProcessTable(),
    ownPID: getpid(),
    parentPID: getppid(),
    write: writer(to: .standardOutput),
    writeError: writer(to: .standardError),
    newID: { UUID().uuidString },
    now: { Date() },
    ownBinaryPath: ownExecutablePath(),
    pathEnv: ProcessInfo.processInfo.environment["PATH"]
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

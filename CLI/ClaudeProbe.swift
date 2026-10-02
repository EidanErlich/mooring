import Darwin
import Foundation
import MooringCLICore
import MooringIPC

/// Collects one pipe's output and leaves `group` once, when the pipe reaches end of file.
private final class PipeCollector: @unchecked Sendable {
    // The lock guards the state, which the pipe's handler writes from its own queue.
    private let lock = NSLock()
    private var data = Data()
    private var finished = false
    private let group: DispatchGroup

    init(group: DispatchGroup, pipe: Pipe) {
        self.group = group
        group.enter()
        pipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                let first = lock.withLock { () -> Bool in
                    defer { finished = true }
                    return !finished
                }
                if first { group.leave() }
            } else {
                lock.withLock { data.append(chunk) }
            }
        }
    }

    var value: Data { lock.withLock { data } }
}

/// Runs a command and returns its stdout when it exits 0 within `timeout` seconds, nil otherwise.
/// Never waits much longer than that, even when the command's children keep its pipes open.
/// (The app's `ProcessRunner` does the same; the two targets share no code.)
func runBounded(_ argv: [String], timeout: TimeInterval) -> Data? {
    guard let executable = argv.first else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = Array(argv.dropFirst())
    let (outPipe, errPipe) = (Pipe(), Pipe())
    process.standardOutput = outPipe
    process.standardError = errPipe
    process.standardInput = FileHandle.nullDevice
    let eof = DispatchGroup()
    let out = PipeCollector(group: eof, pipe: outPipe)
    _ = PipeCollector(group: eof, pipe: errPipe)
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    func detach() {
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
    }
    do {
        try process.run()
    } catch {
        detach()
        return nil
    }
    let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
    if timedOut {
        process.terminate()
        if exited.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
    }
    // Children can keep the pipes open after the command is gone, so give end of file a moment, then move on.
    _ = eof.wait(timeout: .now() + 1)
    detach()
    return timedOut || process.isRunning || process.terminationStatus != 0 ? nil : out.value
}

/// `claude` from the caller's PATH first (the CLI runs in the user's shell), then the usual install locations.
func findClaude(pathEnv: String?, isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
    let onPath = (pathEnv ?? "").split(separator: ":").map { "\($0)/claude" }
    let usual = ClaudeCode.candidatePaths.map { ($0 as NSString).expandingTildeInPath }
    return (onPath + usual).first(where: isExecutable)
}

/// What doctor needs from Claude Code: its version, its plugins, and what the installed plugin was tested with.
/// nil when `claude` isn't found. Blocks for a few seconds at most per command.
func probeClaude(pathEnv: String?) -> ClaudeSnapshot? {
    guard let claude = findClaude(pathEnv: pathEnv) else { return nil }
    let version = runBounded([claude, "--version"], timeout: 3)
        .flatMap { String(bytes: $0, encoding: .utf8) }.flatMap(ClaudeCode.parseVersion)
    let plugins = runBounded([claude, "plugin", "list", "--json"], timeout: 3).flatMap(ClaudeCode.parsePluginList)
    return ClaudeSnapshot(version: version, plugins: plugins, testedWith: plugins.flatMap(testedWithClaudeCode))
}

/// The `testedWithClaudeCode` in the installed Mooring plugin's `mooring.json`.
private func testedWithClaudeCode(_ plugins: [ClaudeCode.InstalledPlugin]) -> String? {
    guard let folder = ClaudeCode.mooringPlugin(in: plugins)?.installPath,
          let data = FileManager.default.contents(atPath: folder + "/mooring.json"),
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    return object["testedWithClaudeCode"] as? String
}

import ArgumentParser
import Foundation
import MooringIPC

/// Runs the `mooring` command line against an environment, so tests can drive it without a socket.
public enum MooringCLI {
    /// Parses `arguments` (without the program name), runs the command and returns the exit status.
    public static func run(_ arguments: [String], environment: CLIEnvironment) async -> Int32 {
        do {
            var parsed = try MooringCommand.parseAsRoot(arguments)
            if let command = parsed as? any CLICommand { return await command.execute(environment) }
            // Help requests and a bare `mooring` parse to commands that print help by throwing from `run()`.
            try parsed.run()
            return 0
        } catch {
            let message = MooringCommand.fullMessage(for: error) + "\n"
            if MooringCommand.exitCode(for: error) == .success {
                environment.write(message)
                return 0
            }
            environment.writeError(message)
            return 1
        }
    }
}

/// A command that runs against the app.
protocol CLICommand {
    func execute(_ env: CLIEnvironment) async -> Int32
}

/// The flags every command takes after its name.
struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Print JSON instead of text.")
    var json = false

    @Flag(name: .customLong("no-launch"), help: "Don't start Mooring if it isn't running.")
    var noLaunch = false
}

struct MooringCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mooring",
        abstract: "Keep your Mac awake from scripts and agents",
        discussion: """
        Turn keep-awake on or off, hold it while a process runs, or manage named leases. \
        Every command takes --json and --no-launch after its name.

        For agents:

          To stay awake while you work, then let go:
            mooring lease acquire <name> --watch-pid auto --reason "…"
            …do the work…
            mooring lease release <name>

          To stay awake exactly as long as a command runs:
            mooring anchor -- <command>
        """,
        version: "mooring 0.2.0-dev",
        subcommands: [OnCommand.self, Off.self, Anchor.self, LeaseGroup.self, Status.self]
    )
}

/// Checks flag values while parsing, turning a bad one into a usage error that exits 1.
func validated<Value>(_ body: () throws -> Value) throws -> Value {
    do {
        return try body()
    } catch CLIError.usage(let message) {
        throw ValidationError(message)
    }
}

/// Reads flag values into the shapes the wire format wants.
enum CLIParse {
    static func duration(_ text: String?, flag: String) throws -> Double? {
        guard let text else { return nil }
        guard let seconds = WireText.parseDuration(text) else {
            throw CLIError.usage("Invalid duration '\(text)' for \(flag). Use forms like 90s, 15m, 2h or 1h30m")
        }
        return seconds
    }

    /// The canonical level name for `text`, or nil when no level was given.
    static func level(_ text: String?) throws -> String? {
        guard let text else { return nil }
        guard let flags = WireText.parseLevel(text) else {
            throw CLIError.usage("Unknown level '\(text)'. Use system, display, lid or display,lid")
        }
        return WireText.levelName(display: flags.display, lid: flags.lid)
    }

    static func pid(_ value: Int32?, flag: String) throws -> Int32? {
        guard let value else { return nil }
        guard value > 0 else { throw CLIError.usage("\(flag) needs a positive process id") }
        return value
    }
}

/// Sends one command's request and prints the reply.
struct CommandRunner {
    let env: CLIEnvironment
    let options: OutputOptions

    func run(_ makeArgs: () throws -> RequestArgs) async -> Int32 {
        let args: RequestArgs
        do {
            args = try makeArgs()
        } catch CLIError.usage(let message) {
            env.writeError("mooring: \(message)\n")
            return 1
        } catch {
            env.writeError("mooring: \(error)\n")
            return 1
        }
        let request = Request(v: WireProtocol.version, id: env.newID(), op: Self.op(of: args), args: args)
        do {
            let response = try await env.client.send(request, launch: !options.noLaunch)
            return report(response, to: request)
        } catch CLIError.unreachable {
            return unreachable()
        } catch CLIError.usage(let message) {
            env.writeError("mooring: \(message)\n")
            return 1
        } catch {
            env.writeError("mooring: Couldn't talk to Mooring\n")
            return 4
        }
    }

    private func report(_ response: Response, to request: Request) -> Int32 {
        if response.ok, let result = response.result {
            if options.json {
                printJSON(result)
            } else {
                env.write(CLIText.human(result, for: request.args, now: env.now()) + trailingNewline(for: result))
            }
            return 0
        }
        let error = response.error ?? WireError(code: .internal, message: "Unexpected reply from Mooring")
        if options.json {
            printJSON(response.ok ? Response.failure(id: response.id, error.code, error.message) : response)
        } else {
            env.writeError("mooring: \(error.message)\n")
        }
        return WireText.exitCode(for: error.code)
    }

    private func unreachable() -> Int32 {
        let message = "Mooring isn't running and couldn't be started"
        if options.json {
            env.write(#"{"ok":false,"error":{"code":"unreachable","message":"\#(message)"}}"# + "\n")
        } else {
            env.writeError("mooring: \(message)\n")
        }
        return WireText.unreachableExitCode
    }

    private func printJSON(_ value: some Encodable) {
        guard let line = try? WireCoding.encodeLine(value), let text = String(bytes: line, encoding: .utf8) else {
            env.writeError("mooring: Couldn't encode the reply\n")
            return
        }
        env.write(text)
    }

    /// Status text already ends with a newline; the one-line results don't.
    private func trailingNewline(for result: ResponseResult) -> String {
        if case .status = result { return "" }
        return "\n"
    }

    private static func op(of args: RequestArgs) -> Op {
        switch args {
        case .acquire: .acquire
        case .renew: .renew
        case .release: .release
        case .status: .status
        }
    }
}

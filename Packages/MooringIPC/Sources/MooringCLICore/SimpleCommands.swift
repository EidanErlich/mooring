import ArgumentParser
import Foundation
import MooringIPC

struct OnCommand: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(commandName: "on", abstract: "Keep the Mac awake")

    @Option(help: "system, display, lid or display,lid. Defaults to the menu bar click level.")
    var level: String?

    @Option(name: .customLong("for"), help: "How long: 90s, 15m, 2h or 1h30m. Defaults to the menu bar click duration.")
    var duration: String?

    @Option(help: "Why, shown in the menu.")
    var reason: String?

    @OptionGroup var output: OutputOptions

    func validate() throws {
        try validated {
            _ = try CLIParse.level(level)
            _ = try CLIParse.duration(duration, flag: "--for")
        }
    }

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run {
            .acquire(AcquireArgs(
                kind: .on, id: nil, level: try CLIParse.level(level), ttl: try CLIParse.duration(duration, flag: "--for"),
                watchPid: nil, reason: reason, agent: nil
            ))
        }
    }
}

struct Off: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(abstract: "Stop keeping the Mac awake from `mooring on`")

    @OptionGroup var output: OutputOptions

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run { .release(ReleaseArgs(kind: .off, id: nil, after: nil)) }
    }
}

struct Status: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(abstract: "Show what is keeping the Mac awake")

    @OptionGroup var output: OutputOptions

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run { .status }
    }
}

struct Anchor: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(abstract: "Keep the Mac awake while a process runs")

    @Option(help: "Watch this process id.")
    var pid: Int32?

    @Option(help: "system, display, lid or display,lid. Defaults to system.")
    var level: String?

    @Option(help: "Why, shown in the menu.")
    var reason: String?

    @Option(help: "Name to show as the owner.")
    var agent: String?

    @Argument(parsing: .postTerminator, help: "A command to run and watch.")
    var command: [String] = []

    @OptionGroup var output: OutputOptions

    func validate() throws {
        try validated {
            _ = try CLIParse.level(level)
            _ = try CLIParse.pid(pid, flag: "--pid")
        }
    }

    func execute(_ env: CLIEnvironment) async -> Int32 {
        if !command.isEmpty {
            guard pid == nil else {
                env.writeError("mooring: Use either --pid or -- <command>\n")
                return 1
            }
            return await AnchoredCommand(
                env: env, options: output, command: command, level: level, reason: reason, agent: agent
            ).run()
        }
        return await CommandRunner(env: env, options: output).run {
            guard let watched = try CLIParse.pid(pid, flag: "--pid") else {
                throw CLIError.usage("Give --pid <pid> or -- <command>")
            }
            return .acquire(AcquireArgs(
                kind: .anchor, id: nil, level: try CLIParse.level(level), ttl: nil, watchPid: watched, reason: reason, agent: agent
            ))
        }
    }
}

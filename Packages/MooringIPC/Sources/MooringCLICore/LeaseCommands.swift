import ArgumentParser
import Foundation
import MooringIPC

struct LeaseGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lease",
        abstract: "Hold, renew and release a named lease",
        subcommands: [LeaseAcquire.self, LeaseRenew.self, LeaseRelease.self]
    )
}

struct LeaseAcquire: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(commandName: "acquire", abstract: "Hold the Mac awake under a name")

    @Argument(help: "The lease's name.")
    var id: String

    @Option(help: "How long: 90s, 15m, 2h or 1h30m.")
    var ttl: String?

    @Option(name: .customLong("watch-pid"), help: "Hold while this process runs: a process id, or auto for the calling agent.")
    var watchPid: String?

    @Option(help: "system or display.")
    var level: String?

    @Option(help: "Why, shown in the menu.")
    var reason: String?

    @Option(help: "Name to show as the owner. Defaults to the watched process.")
    var agent: String?

    @OptionGroup var output: OutputOptions

    func validate() throws {
        try validated {
            _ = try CLIParse.level(level)
            _ = try CLIParse.duration(ttl, flag: "--ttl")
            _ = try watchTarget()
        }
    }

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run {
            var owner = agent
            var watched: Int32?
            switch try watchTarget() {
            case .auto:
                guard let entry = ProcessTree.autoWatch(from: env.parentPID, in: env.processes) else {
                    throw CLIError.usage("Couldn't find a process to watch")
                }
                watched = entry.pid
                owner = owner ?? ProcessTree.agentName(for: entry.name)
            case .pid(let pid):
                watched = pid
            case nil:
                break
            }
            return .acquire(AcquireArgs(
                kind: .lease, id: id, level: try CLIParse.level(level), ttl: try CLIParse.duration(ttl, flag: "--ttl"),
                watchPid: watched, reason: reason, agent: owner
            ))
        }
    }

    private enum WatchTarget {
        case auto
        case pid(Int32)
    }

    private func watchTarget() throws -> WatchTarget? {
        guard let watchPid else { return nil }
        if watchPid == "auto" { return .auto }
        guard let pid = Int32(watchPid), pid > 0 else {
            throw CLIError.usage("--watch-pid takes auto or a process id, not '\(watchPid)'")
        }
        return .pid(pid)
    }
}

struct LeaseRenew: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(commandName: "renew", abstract: "Extend a lease")

    @Argument(help: "The lease's name.")
    var id: String

    @Option(help: "How long from now. Defaults to the lease's last length.")
    var ttl: String?

    @OptionGroup var output: OutputOptions

    func validate() throws {
        try validated { _ = try CLIParse.duration(ttl, flag: "--ttl") }
    }

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run {
            .renew(RenewArgs(id: id, ttl: try CLIParse.duration(ttl, flag: "--ttl")))
        }
    }
}

struct LeaseRelease: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(commandName: "release", abstract: "Let go of a lease")

    @Argument(help: "The lease's name.")
    var id: String

    @Option(help: "Release after this long instead of now. Only ever shortens the lease.")
    var after: String?

    @OptionGroup var output: OutputOptions

    func validate() throws {
        try validated { _ = try CLIParse.duration(after, flag: "--after") }
    }

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run {
            .release(ReleaseArgs(kind: .lease, id: id, after: try CLIParse.duration(after, flag: "--after")))
        }
    }
}

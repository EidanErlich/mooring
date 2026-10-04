import ArgumentParser
import Foundation
import MooringIPC

struct WinGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "win",
        abstract: "List and arrange windows",
        discussion: """
        Windows must be on in Mooring (Windows › Turn On…). Arrange takes one <app>=<region> per window, \
        like chrome=right-half or iterm=bottom-left@left, or a frame as fractions: slack=0,0,0.5,0.5. \
        `mooring win list-regions` prints every region name; regions only move and resize windows.
        """,
        subcommands: [WinList.self, WinArrange.self, WinDo.self, WinUndo.self, WinLayoutGroup.self, WinListRegions.self]
    )
}

/// Reads `win` arguments into the shapes the wire format wants.
enum WinParse {
    /// The most a plan file or stdin may hold.
    static let maxPlanBytes = 1_048_576

    /// `app=region`, `app=region@screen` or `app=x,y,w,h[@screen]` (fractions of the screen).
    static func placement(_ text: String) throws -> WinPlacement {
        let shape = "Expected <app>=<region> or <app>=x,y,w,h (optionally @screen), not '\(text)'"
        guard let equals = text.lastIndex(of: "=") else { throw CLIError.usage(shape) }
        let app = text[..<equals].trimmingCharacters(in: .whitespaces)
        var target = String(text[text.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        var screen: String?
        if let marker = target.lastIndex(of: "@") {
            let name = target[target.index(after: marker)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw CLIError.usage("'\(text)' has an empty screen after @. Use main, left, right or an index") }
            screen = name
            target = String(target[..<marker]).trimmingCharacters(in: .whitespaces)
        }
        guard !app.isEmpty, !target.isEmpty else { throw CLIError.usage(shape) }
        if target.contains(",") {
            return WinPlacement(app: app, frame: try frame(target, in: text), screen: screen)
        }
        return WinPlacement(app: app, region: target, screen: screen)
    }

    private static func frame(_ target: String, in text: String) throws -> WinFrame {
        let values = target.split(separator: ",", omittingEmptySubsequences: false)
            .map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 4, case let numbers = values.compactMap({ $0 }), numbers.count == 4, numbers.allSatisfy(\.isFinite) else {
            throw CLIError.usage("A frame needs four numbers, x,y,w,h as fractions of the screen: '\(text)'")
        }
        return WinFrame(x: numbers[0], y: numbers[1], w: numbers[2], h: numbers[3])
    }

    /// The plan in a file, or on stdin for `-`, decoded and checked.
    static func plan(from source: String, env: CLIEnvironment) throws -> WinPlan {
        let data: Data
        if source == "-" {
            data = env.readInput(maxPlanBytes + 1)
        } else {
            guard let read = FileManager.default.contents(atPath: source) else {
                throw CLIError.usage("Couldn't read the plan at \(source)")
            }
            data = read
        }
        guard data.count <= maxPlanBytes else { throw CLIError.usage("The plan is too large (the limit is 1 MiB)") }
        do {
            return try JSONDecoder().decode(WinPlan.self, from: data)
        } catch let error as DecodingError {
            throw CLIError.usage("Couldn't read the plan: \(describe(error))")
        } catch {
            throw CLIError.usage("Couldn't read the plan: \(error.localizedDescription)")
        }
    }

    /// The plan with every placement checked and tidied, or a usage error naming the first problem.
    static func checked(_ plan: WinPlan) throws -> WinPlan {
        do {
            return try plan.validated()
        } catch let error as WireError {
            throw CLIError.usage(error.message)
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().drop { $0 == "." }.description
        }
        switch error {
        case .keyNotFound(let key, let context): return "missing \"\(key.stringValue)\" at \(path(context))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context): return "wrong value at \(path(context))"
        case .dataCorrupted: return "it isn't valid JSON"
        @unknown default: return "it isn't a window plan"
        }
    }
}

struct WinList: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "Show running apps, their windows and the screens")

    @OptionGroup var output: OutputOptions

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run { .winList() }
    }
}

struct WinListRegions: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(commandName: "list-regions", abstract: "Print every region name")

    @OptionGroup var output: OutputOptions

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run({ .winList() }, render: { result in
            guard case .winList(let list) = result else { return "" }
            return list.regions.joined(separator: "\n")
        })
    }
}

struct WinArrange: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(
        commandName: "arrange", abstract: "Move windows into place with one plan",
        discussion: "Exits 0 only when every placement is ok, and 2 when any isn't."
    )

    @Argument(help: "<app>=<region>[@screen], or <app>=x,y,w,h[@screen] with fractions of the screen.")
    var placements: [String] = []

    @Option(help: "Read a JSON plan from this file, or from stdin for -.")
    var plan: String?

    @Flag(help: "Open apps that aren't running.")
    var launch = false

    @Flag(help: "Show each target frame briefly before moving.")
    var preview = false

    @OptionGroup var output: OutputOptions

    func validate() throws {
        try validated {
            if plan != nil, !placements.isEmpty { throw CLIError.usage("Give placements or --plan, not both") }
            if plan == nil, placements.isEmpty {
                throw CLIError.usage("Give at least one <app>=<region> placement, or --plan <file|->")
            }
            _ = try placements.map(WinParse.placement)
        }
    }

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run {
            var arranged = try plan.map { try WinParse.plan(from: $0, env: env) }
                ?? WinPlan(placements: try placements.map(WinParse.placement))
            if launch { arranged.launch = true }
            if preview { arranged.preview = true }
            arranged.client = nil
            return .winArrange(try WinParse.checked(arranged))
        }
    }
}

struct WinDo: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(
        commandName: "do", abstract: "Put one window in a region, like left-half or maximize",
        discussion: "Moves the frontmost app's window unless --app says otherwise."
    )

    @Argument(help: "A region name; `mooring win list-regions` prints them all.")
    var action: String

    @Option(help: "The app to move. Defaults to the frontmost app.")
    var app: String?

    @Option(help: "main, left, right or an index. Defaults to the screen the window is on.")
    var screen: String?

    @OptionGroup var output: OutputOptions

    func validate() throws {
        try validated {
            if action.trimmingCharacters(in: .whitespaces).isEmpty { throw CLIError.usage("Give a region name") }
        }
    }

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run {
            let placement = WinPlacement(app: app ?? WinPlacement.frontmostApp, region: action, screen: screen)
            return .winArrange(try WinParse.checked(WinPlan(placements: [placement])))
        }
    }
}

struct WinUndo: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(commandName: "undo", abstract: "Put the windows of the last arrangement back")

    @OptionGroup var output: OutputOptions

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run { .winUndo(WinUndoArgs()) }
    }
}

struct WinLayoutGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "layout", abstract: "Save and apply named layouts",
        subcommands: [WinLayoutSave.self, WinLayoutApply.self, WinLayoutList.self, WinLayoutDelete.self]
    )
}

/// The name a layout command was given, checked.
private func layoutName(_ name: String) throws -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw CLIError.usage("Give the layout's name") }
    return trimmed
}

struct WinLayoutSave: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(commandName: "save", abstract: "Save where the frontmost window of each app is")

    @Argument(help: "The layout's name.")
    var name: String

    @OptionGroup var output: OutputOptions

    func validate() throws { try validated { _ = try layoutName(name) } }

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run { .winLayout(WinLayoutArgs(action: "save", name: try layoutName(name))) }
    }
}

struct WinLayoutApply: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(
        commandName: "apply", abstract: "Arrange windows as a saved layout, opening apps that aren't running",
        discussion: "Exits 0 only when every placement is ok, and 2 when any isn't."
    )

    @Argument(help: "The layout's name.")
    var name: String

    @OptionGroup var output: OutputOptions

    func validate() throws { try validated { _ = try layoutName(name) } }

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run { .winLayout(WinLayoutArgs(action: "apply", name: try layoutName(name))) }
    }
}

struct WinLayoutList: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "Print the saved layouts' names")

    @OptionGroup var output: OutputOptions

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run { .winLayout(WinLayoutArgs(action: "list")) }
    }
}

struct WinLayoutDelete: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a saved layout")

    @Argument(help: "The layout's name.")
    var name: String

    @OptionGroup var output: OutputOptions

    func validate() throws { try validated { _ = try layoutName(name) } }

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run { .winLayout(WinLayoutArgs(action: "delete", name: try layoutName(name))) }
    }
}

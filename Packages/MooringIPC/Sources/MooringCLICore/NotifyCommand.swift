import ArgumentParser
import Foundation
import MooringIPC

/// `mooring notify`: posts a notification through the app, which names the caller and rate-limits it.
struct NotifyCommand: ParsableCommand, CLICommand {
    static let configuration = CommandConfiguration(
        commandName: "notify", abstract: "Post a notification, for when a long job finishes and the user may be away"
    )

    @Argument(help: "The notification's title.")
    var title: String

    @Argument(help: "Text under the title.")
    var body: String?

    @OptionGroup var output: OutputOptions

    func execute(_ env: CLIEnvironment) async -> Int32 {
        await CommandRunner(env: env, options: output).run {
            .notify(NotifyArgs(title: title, body: body, client: nil))
        }
    }
}

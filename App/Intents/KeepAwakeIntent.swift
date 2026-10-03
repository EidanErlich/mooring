import AppIntents
import Foundation

/// "Keep Mac Awake": the menu's On switch, with an optional length and a level.
struct KeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Keeps your Mac awake until you turn it off, or for the time you give.")
    static let openAppWhenRun = false

    @Parameter(title: "Duration", description: "Leave empty to stay awake until turned off.")
    var duration: Measurement<UnitDuration>?

    @Parameter(title: "Level", default: .normal)
    var level: IntentLevel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = try await IntentActions.shared.keepAwake(
            duration: duration?.converted(to: .seconds).value, level: level
        )
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

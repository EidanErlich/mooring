import AppIntents

/// "Let Mac Sleep": the menu's On switch, off.
struct LetSleepIntent: AppIntent {
    static let title: LocalizedStringResource = "Let Mac Sleep"
    static let description = IntentDescription("Ends Mooring's session, so your Mac can sleep as usual.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentActions.shared.letSleep()
        return .result(dialog: "Your Mac can sleep now.")
    }
}

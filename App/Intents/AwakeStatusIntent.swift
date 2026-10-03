import AppIntents

/// "Get Awake Status": whether Mooring is keeping the Mac awake, and how.
struct AwakeStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Awake Status"
    static let description = IntentDescription("Tells you whether Mooring is keeping your Mac awake.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<AwakeStatusEntity> & ProvidesDialog {
        let status = try await IntentActions.shared.status()
        return .result(value: status, dialog: IntentDialog(stringLiteral: status.summary))
    }
}

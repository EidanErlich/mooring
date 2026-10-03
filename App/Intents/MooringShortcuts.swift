import AppIntents

/// The phrases that run Mooring's actions from Siri and Spotlight, and put them in the Shortcuts app.
struct MooringShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: KeepAwakeIntent(),
            phrases: ["Keep my Mac awake with \(.applicationName)"],
            shortTitle: "Keep Mac Awake",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: LetSleepIntent(),
            phrases: ["Let my Mac sleep with \(.applicationName)"],
            shortTitle: "Let Mac Sleep",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: AwakeStatusIntent(),
            phrases: ["Is my Mac staying awake with \(.applicationName)"],
            shortTitle: "Get Awake Status",
            systemImageName: "questionmark.circle"
        )
    }
}

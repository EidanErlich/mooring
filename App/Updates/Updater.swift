import AppKit
import Defaults
import Observation
import Sparkle

/// What `UpdatesController` drives: Sparkle in the app, a fake in tests.
@MainActor
protocol UpdaterDriving: AnyObject {
    /// Starts the updater, once, with its automatic checks on or off.
    func start(automaticallyChecks: Bool)
    var automaticallyChecksForUpdates: Bool { get set }
    /// A check the user asked for, showing its result.
    func checkForUpdates()
}

/// `checkForUpdates` and `didAskForUpdates`.
@MainActor
protocol UpdatesSettings: AnyObject {
    var checkForUpdates: Bool { get set }
    var didAskForUpdates: Bool { get set }
}

/// The consent alert's text.
struct UpdatesQuestion: Equatable {
    let message: String
    let detail: String
    let confirm: String
    let cancel: String

    static let consent = UpdatesQuestion(
        message: "Check for updates automatically?",
        detail: "Mooring can look for new versions about once a day. You can change this in Settings → Advanced.",
        confirm: "Check Automatically", cancel: "Not Now")
}

/// Owns the updater. With no public key it is unavailable: Sparkle is never created, nothing is asked and
/// nothing reaches the network. With a key, nothing is checked until the user agrees or presses Check Now.
@MainActor @Observable
final class UpdatesController {
    let isAvailable: Bool
    private(set) var checksAutomatically: Bool
    /// The gentle reminder for scheduled updates (Sparkle's user driver delegate).
    let reminder: UpdateReminder

    @ObservationIgnored private let settings: any UpdatesSettings
    @ObservationIgnored private let makeUpdater: @MainActor () -> any UpdaterDriving
    @ObservationIgnored private let ask: @MainActor (UpdatesQuestion) -> Bool
    @ObservationIgnored private var updater: (any UpdaterDriving)?

    /// `makeUpdater` runs at most once, the first time the updater is needed. `ask` shows the consent alert
    /// and returns true for Check Automatically.
    init(publicKey: String, settings: any UpdatesSettings, reminder: UpdateReminder,
         makeUpdater: @escaping @MainActor () -> any UpdaterDriving,
         ask: @escaping @MainActor (UpdatesQuestion) -> Bool) {
        isAvailable = !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.settings = settings
        self.reminder = reminder
        self.makeUpdater = makeUpdater
        self.ask = ask
        checksAutomatically = settings.checkForUpdates
    }

    /// At app launch: asks once per install, then starts the updater only if automatic checks are on.
    func launch() {
        guard isAvailable else { return }
        if !settings.didAskForUpdates {
            let agreed = ask(.consent)
            settings.didAskForUpdates = true
            settings.checkForUpdates = agreed
            checksAutomatically = agreed
        }
        if settings.checkForUpdates { startedUpdater() }
    }

    /// Settings → Advanced's toggle. Turning it off never creates the updater.
    func setChecksAutomatically(_ isOn: Bool) {
        guard isAvailable else { return }
        settings.checkForUpdates = isOn
        checksAutomatically = isOn
        if let updater {
            updater.automaticallyChecksForUpdates = isOn
        } else if isOn {
            startedUpdater()
        }
    }

    /// True while a scheduled update waits for the user: the dropdown then shows "Update Available…".
    var updateAvailable: Bool { isAvailable && reminder.isPending }

    /// Settings → Advanced's Check Now, and the dropdown's "Update Available…" (which brings the update forward).
    func checkNow() {
        guard isAvailable else { return }
        startedUpdater().checkForUpdates()
    }

    /// The updater, made and started on first use with the current automatic-check setting.
    @discardableResult
    private func startedUpdater() -> any UpdaterDriving {
        if let updater { return updater }
        let made = makeUpdater()
        made.start(automaticallyChecks: settings.checkForUpdates)
        updater = made
        return made
    }
}

extension UpdatesController {
    /// The app's controller, keyed by Info.plist's SUPublicEDKey (from MOORING_SPARKLE_PUBLIC_KEY).
    /// `poster` posts the reminder for a scheduled update found while Mooring is in the background.
    static func live(bundle: Bundle = .main, poster: any NotificationPosting) -> UpdatesController {
        let reminder = UpdateReminder(poster: poster)
        return UpdatesController(
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "",
            settings: DefaultsUpdatesSettings(),
            reminder: reminder,
            makeUpdater: { LiveSparkleUpdater(reminder: reminder) },
            ask: askWithAlert)
    }

    private static func askWithAlert(_ question: UpdatesQuestion) -> Bool {
        let alert = NSAlert()
        alert.messageText = question.message
        alert.informativeText = question.detail
        alert.addButton(withTitle: question.confirm)
        alert.addButton(withTitle: question.cancel)
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}

@MainActor
final class DefaultsUpdatesSettings: UpdatesSettings {
    var checkForUpdates: Bool {
        get { Defaults[.checkForUpdates] }
        set { Defaults[.checkForUpdates] = newValue }
    }

    var didAskForUpdates: Bool {
        get { Defaults[.didAskForUpdates] }
        set { Defaults[.didAskForUpdates] = newValue }
    }
}

/// Gentle reminders for scheduled updates (Sparkle 2's `SPUStandardUserDriverDelegate`). Mooring has no Dock icon
/// and can't be Cmd-Tabbed to, so an update alert Sparkle shows behind other apps is easy to never see. Sparkle shows
/// a scheduled update itself only when it would be in focus; otherwise Mooring posts a notification and adds
/// "Update Available…" to the dropdown, which brings the update forward through Check Now.
@MainActor @Observable
final class UpdateReminder {
    /// The one reminder notification's id; a newer update replaces it.
    static let notificationID = "mooring.update-available"
    static let body = "Open the menu bar icon to update."

    /// True from a background scheduled update until the user looks at it or the update session ends.
    private(set) var isPending = false

    @ObservationIgnored private let poster: any NotificationPosting

    init(poster: any NotificationPosting) {
        self.poster = poster
    }

    /// Sparkle's `supportsGentleScheduledUpdateReminders`.
    let supportsGentleScheduledUpdateReminders = true

    static func title(version: String) -> String { "Mooring \(version) is available" }

    /// Sparkle's `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)`: Sparkle shows the
    /// update itself only when it would be in focus; otherwise Mooring reminds.
    func sparkleShowsScheduledUpdate(immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    /// Sparkle's `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)`. A scheduled update Sparkle left to
    /// Mooring sets the reminder and posts the notification (if notifications are allowed). The returned task is
    /// the post, for tests to wait on.
    @discardableResult
    func willShowUpdate(version: String, sparkleShows: Bool, userInitiated: Bool) -> Task<Void, Never>? {
        guard !sparkleShows, !userInitiated else { return nil }
        isPending = true
        let poster = poster
        return Task {
            guard await poster.authorize() else { return }
            await poster.post(id: Self.notificationID, title: Self.title(version: version), body: Self.body,
                              userInfo: [:], category: nil)
        }
    }

    /// Sparkle's `standardUserDriverDidReceiveUserAttention(forUpdate:)`: the user is looking at the update.
    func didReceiveUserAttention() {
        clear()
    }

    /// Sparkle's `standardUserDriverWillFinishUpdateSession()`: installed, skipped, dismissed or failed.
    func willFinishUpdateSession() {
        clear()
    }

    private func clear() {
        guard isPending else { return }
        isPending = false
        poster.withdraw(id: Self.notificationID)
    }
}

/// Sparkle's standard updater and UI. Only `UpdatesController.live` makes one, and only with a public key.
@MainActor
final class LiveSparkleUpdater: UpdaterDriving {
    private let delegate: SparkleUserDriverDelegate
    private let controller: SPUStandardUpdaterController

    init(reminder: UpdateReminder) {
        delegate = SparkleUserDriverDelegate(reminder: reminder)
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: delegate)
    }

    func start(automaticallyChecks: Bool) {
        controller.updater.automaticallyChecksForUpdates = automaticallyChecks
        controller.startUpdater()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Hands Sparkle's user driver callbacks (always on the main thread) to `UpdateReminder`, which holds the logic.
@MainActor
private final class SparkleUserDriverDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private let reminder: UpdateReminder

    init(reminder: UpdateReminder) {
        self.reminder = reminder
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        reminder.supportsGentleScheduledUpdateReminders
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        reminder.sparkleShowsScheduledUpdate(immediateFocus: immediateFocus)
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        reminder.willShowUpdate(version: update.displayVersionString, sparkleShows: handleShowingUpdate,
                                userInitiated: state.userInitiated)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        reminder.didReceiveUserAttention()
    }

    func standardUserDriverWillFinishUpdateSession() {
        reminder.willFinishUpdateSession()
    }
}

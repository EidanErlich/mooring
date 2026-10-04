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

    @ObservationIgnored private let settings: any UpdatesSettings
    @ObservationIgnored private let makeUpdater: @MainActor () -> any UpdaterDriving
    @ObservationIgnored private let ask: @MainActor (UpdatesQuestion) -> Bool
    @ObservationIgnored private var updater: (any UpdaterDriving)?

    /// `makeUpdater` runs at most once, the first time the updater is needed. `ask` shows the consent alert
    /// and returns true for Check Automatically.
    init(publicKey: String, settings: any UpdatesSettings,
         makeUpdater: @escaping @MainActor () -> any UpdaterDriving,
         ask: @escaping @MainActor (UpdatesQuestion) -> Bool) {
        isAvailable = !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.settings = settings
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

    /// Settings → Advanced's Check Now.
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
    static func live(bundle: Bundle = .main) -> UpdatesController {
        UpdatesController(
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "",
            settings: DefaultsUpdatesSettings(),
            makeUpdater: { LiveSparkleUpdater() },
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

/// Sparkle's standard updater and UI. Only `UpdatesController.live` makes one, and only with a public key.
@MainActor
final class LiveSparkleUpdater: UpdaterDriving {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

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

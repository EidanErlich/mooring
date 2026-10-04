import AppKit
import SwiftUI
import Testing
@testable import Mooring

/// Stands in for Sparkle: records what the controller asks of it. Never touches the network.
@MainActor
final class FakeUpdater: UpdaterDriving {
    private(set) var starts: [Bool] = []
    private(set) var checks = 0
    var automaticallyChecksForUpdates = false

    func start(automaticallyChecks: Bool) {
        starts.append(automaticallyChecks)
        automaticallyChecksForUpdates = automaticallyChecks
    }

    func checkForUpdates() {
        checks += 1
    }
}

@MainActor
final class FakeUpdatesSettings: UpdatesSettings {
    var checkForUpdates: Bool
    var didAskForUpdates: Bool

    init(checkForUpdates: Bool = false, didAskForUpdates: Bool = false) {
        self.checkForUpdates = checkForUpdates
        self.didAskForUpdates = didAskForUpdates
    }
}

/// A controller over fakes, counting updaters made and questions asked.
@MainActor
private final class UpdatesHarness {
    let settings: FakeUpdatesSettings
    private(set) var updaters: [FakeUpdater] = []
    private(set) var questions: [UpdatesQuestion] = []
    private(set) var controller: UpdatesController!

    var updater: FakeUpdater? { updaters.last }

    init(publicKey: String = "test-public-key", answer: Bool = false, settings: FakeUpdatesSettings = FakeUpdatesSettings()) {
        self.settings = settings
        controller = UpdatesController(
            publicKey: publicKey, settings: settings, reminder: UpdateReminder(poster: FakeNotificationPoster()),
            makeUpdater: { [unowned self] in
                let updater = FakeUpdater()
                updaters.append(updater)
                return updater
            },
            ask: { [unowned self] question in
                questions.append(question)
                return answer
            })
    }
}

@MainActor
struct UpdatesControllerTests {
    /// Off means no network: with no public key nothing is asked, made, started or checked, whatever is called.
    @Test func noKeyMeansNoUpdater() {
        for key in ["", "  \n"] {
            let harness = UpdatesHarness(
                publicKey: key, answer: true, settings: FakeUpdatesSettings(checkForUpdates: true, didAskForUpdates: true))
            let updates = harness.controller!
            #expect(!updates.isAvailable)
            updates.launch()
            updates.checkNow()
            updates.setChecksAutomatically(true)
            #expect(harness.updaters.isEmpty)
            #expect(harness.questions.isEmpty)
        }
        let fresh = UpdatesHarness(publicKey: "", answer: true)
        fresh.controller.launch()
        #expect(fresh.questions.isEmpty)
        #expect(!fresh.settings.didAskForUpdates)
        #expect(!fresh.settings.checkForUpdates)
    }

    /// The first launch with a key asks once, with the spec's strings; later launches don't ask again.
    @Test func asksOnceWithKey() {
        let harness = UpdatesHarness(answer: false)
        #expect(harness.controller.isAvailable)
        harness.controller.launch()
        #expect(harness.questions == [UpdatesQuestion.consent])
        #expect(harness.settings.didAskForUpdates)
        harness.controller.launch()
        #expect(harness.questions.count == 1)

        let relaunched = UpdatesHarness(answer: true, settings: harness.settings)
        relaunched.controller.launch()
        #expect(relaunched.questions.isEmpty)

        #expect(UpdatesQuestion.consent.message == "Check for updates automatically?")
        #expect(UpdatesQuestion.consent.confirm == "Check Automatically")
        #expect(UpdatesQuestion.consent.cancel == "Not Now")
    }

    /// "Not Now" leaves automatic checks off, and no updater is made, so nothing is scheduled.
    @Test func notNowLeavesChecksOff() {
        let harness = UpdatesHarness(answer: false)
        harness.controller.launch()
        #expect(!harness.settings.checkForUpdates)
        #expect(!harness.controller.checksAutomatically)
        #expect(harness.updaters.isEmpty)
    }

    /// "Check Automatically" turns checks on and starts the updater with them on; a later launch starts it again.
    @Test func checkAutomaticallyStartsUpdater() throws {
        let harness = UpdatesHarness(answer: true)
        harness.controller.launch()
        #expect(harness.settings.checkForUpdates)
        #expect(harness.controller.checksAutomatically)
        let updater = try #require(harness.updater)
        #expect(harness.updaters.count == 1)
        #expect(updater.starts == [true])
        #expect(updater.checks == 0)

        let relaunched = UpdatesHarness(answer: false, settings: harness.settings)
        relaunched.controller.launch()
        #expect(relaunched.questions.isEmpty)
        #expect(relaunched.updater?.starts == [true])
    }

    /// The Settings toggle starts the updater the first time it's turned on, and later only flips its checks.
    @Test func toggleStartsOnceAndFlipsChecks() throws {
        let harness = UpdatesHarness(answer: false)
        harness.controller.launch()
        harness.controller.setChecksAutomatically(false)
        #expect(harness.updaters.isEmpty)

        harness.controller.setChecksAutomatically(true)
        let updater = try #require(harness.updater)
        #expect(updater.starts == [true])
        #expect(harness.settings.checkForUpdates)

        harness.controller.setChecksAutomatically(false)
        #expect(!updater.automaticallyChecksForUpdates)
        #expect(!harness.settings.checkForUpdates)
        #expect(!harness.controller.checksAutomatically)
        harness.controller.setChecksAutomatically(true)
        #expect(updater.automaticallyChecksForUpdates)
        #expect(updater.starts == [true])
        #expect(harness.updaters.count == 1)
    }

    /// Check Now checks through the updater, starting it with automatic checks still off if the user said Not Now.
    @Test func checkNowCallsUpdater() throws {
        let harness = UpdatesHarness(answer: false)
        harness.controller.launch()
        harness.controller.checkNow()
        let updater = try #require(harness.updater)
        #expect(updater.starts == [false])
        #expect(updater.checks == 1)
        harness.controller.checkNow()
        #expect(updater.checks == 2)
        #expect(harness.updaters.count == 1)
        #expect(!harness.settings.checkForUpdates)
    }

    /// The Updates section (toggle and Check Now) is shown only with a key; laying the page out makes no updater.
    @Test func advancedHidesUpdatesWithoutKey() {
        let noKey = UpdatesHarness(publicKey: "")
        let withKey = UpdatesHarness()
        #expect(!AdvancedSettingsPage.sections(updates: nil).contains(.updates))
        #expect(!AdvancedSettingsPage.sections(updates: noKey.controller).contains(.updates))
        #expect(AdvancedSettingsPage.sections(updates: withKey.controller).contains(.updates))
        #expect(AdvancedSettingsPage.updatesToggleTitle == "Check for updates automatically")
        #expect(AdvancedSettingsPage.checkNowTitle == "Check Now")

        for harness in [noKey, withKey] {
            let size = layOut(AdvancedSettingsPage(engine: nil, updates: harness.controller))
            #expect(size.width > 0 && size.height > 0)
            #expect(harness.updaters.isEmpty)
        }
    }

    /// A scheduled update Sparkle would show behind other apps is Mooring's to show: a notification and the
    /// dropdown's item. One Sparkle shows in focus, or one the user asked for, posts nothing.
    @Test func scheduledUpdateInBackgroundPostsNotification() async {
        let poster = FakeNotificationPoster()
        let reminder = UpdateReminder(poster: poster)
        #expect(reminder.supportsGentleScheduledUpdateReminders)
        #expect(reminder.sparkleShowsScheduledUpdate(immediateFocus: true))
        #expect(!reminder.sparkleShowsScheduledUpdate(immediateFocus: false))
        #expect(!reminder.isPending)

        await reminder.willShowUpdate(version: "0.1.1", sparkleShows: false, userInitiated: false)?.value
        #expect(reminder.isPending)
        #expect(poster.posts == [FakeNotificationPoster.Post(
            id: UpdateReminder.notificationID, title: "Mooring 0.1.1 is available",
            body: "Open the menu bar icon to update.", userInfo: [:], category: nil)])

        // Sparkle shows it in focus, or the user asked: nothing to remind about.
        for (sparkleShows, userInitiated) in [(true, false), (true, true)] {
            let quiet = FakeNotificationPoster()
            let other = UpdateReminder(poster: quiet)
            await other.willShowUpdate(version: "0.1.1", sparkleShows: sparkleShows, userInitiated: userInitiated)?.value
            #expect(!other.isPending)
            #expect(quiet.posts.isEmpty)
        }

        // Notifications off: the dropdown still says so.
        let denied = FakeNotificationPoster()
        denied.authorized = false
        let unannounced = UpdateReminder(poster: denied)
        await unannounced.willShowUpdate(version: "0.1.1", sparkleShows: false, userInitiated: false)?.value
        #expect(unannounced.isPending)
        #expect(denied.posts.isEmpty)
    }

    /// Looking at the update, or the update session ending, clears the reminder and its notification.
    @Test func userAttentionClearsReminder() async {
        let poster = FakeNotificationPoster()
        let reminder = UpdateReminder(poster: poster)
        await reminder.willShowUpdate(version: "0.1.1", sparkleShows: false, userInitiated: false)?.value
        reminder.didReceiveUserAttention()
        #expect(!reminder.isPending)
        #expect(poster.withdrawn == [UpdateReminder.notificationID])

        await reminder.willShowUpdate(version: "0.1.2", sparkleShows: false, userInitiated: false)?.value
        #expect(reminder.isPending)
        reminder.willFinishUpdateSession()
        #expect(!reminder.isPending)

        // The controller reports it only while it's pending, and only with a key.
        let harness = UpdatesHarness()
        #expect(!harness.controller.updateAvailable)
        await harness.controller.reminder.willShowUpdate(version: "0.1.1", sparkleShows: false, userInitiated: false)?.value
        #expect(harness.controller.updateAvailable)
        harness.controller.reminder.didReceiveUserAttention()
        #expect(!harness.controller.updateAvailable)
        let noKey = UpdatesHarness(publicKey: "")
        await noKey.controller.reminder.willShowUpdate(version: "0.1.1", sparkleShows: false, userInitiated: false)?.value
        #expect(!noKey.controller.updateAvailable)
    }

    /// Sparkle reads these from Info.plist: the SPEC's feed, and no checks of its own until Mooring turns them on.
    @Test func infoPlistPointsAtFeedWithChecksOff() {
        let bundle = Bundle(for: AppDelegate.self)
        #expect(bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
            == "https://eidanerlich.github.io/mooring/appcast.xml")
        #expect(bundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool == false)
        #expect(bundle.object(forInfoDictionaryKey: "SUPublicEDKey") is String)
    }

    private func layOut(_ view: some View) -> NSSize {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        return host.fittingSize
    }
}

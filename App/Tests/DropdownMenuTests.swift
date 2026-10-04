import AppKit
import AwakeKit
import Foundation
import Testing
import WindowKit
@testable import Mooring

@MainActor
struct DropdownMenuTests {
    func ids(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : $0.identifier!.rawValue }
    }

    func makeMenuAndEngine(
        helperEnabled: @escaping () -> Bool = { true },
        runningApps: @escaping () -> [NSRunningApplication] = { [] },
        model: DropdownModel = DropdownModel(),
        needsLidConfirmation: @escaping () -> Bool = { false },
        confirmLidOnBattery: @escaping () -> Void = {},
        windows: WindowsController? = nil,
        windowActions: WindowActions = WindowActions(menuActions: { _ in [] }, perform: { _, _ in }, frontmostPID: { nil }),
        clipboard: ClipboardController? = nil,
        updateAvailable: @escaping () -> Bool = { false },
        checkForUpdate: @escaping () -> Void = {}
    ) -> (DropdownMenu, AwakeEngine) {
        let engine = AwakeEngine(assertions: NullAssertions(), store: MemoryStore(), processes: AliveProcesses(),
                                 lid: LidController(helper: FakeLidHelper()), settings: { AwakeSettings() })
        let menu = DropdownMenu(engine: engine, model: model, helperEnabled: helperEnabled,
                                runningApps: runningApps, openSettings: {},
                                windows: windows ?? makeWindows(.off), windowActions: windowActions,
                                clipboard: clipboard ?? Self.offClipboard(),
                                needsLidConfirmation: { _ in needsLidConfirmation() }, confirmLidOnBattery: confirmLidOnBattery,
                                updateAvailable: updateAvailable, checkForUpdate: checkForUpdate)
        return (menu, engine)
    }

    static func offClipboard() -> ClipboardController {
        ClipboardController(settings: FakeClipboardSettings(enabled: false)) { _ in FakeClipKit() }
    }

    private func makeMenu(
        helperEnabled: @escaping () -> Bool = { true },
        runningApps: @escaping () -> [NSRunningApplication] = { [] },
        model: DropdownModel = DropdownModel()
    ) -> DropdownMenu {
        makeMenuAndEngine(helperEnabled: helperEnabled, runningApps: runningApps, model: model).0
    }

    @Test func rootItemsInOrder() {
        #expect(ids(makeMenu().root) == ["header", "-", "awake", "windows", "clipboard", "-", "settings", "quit"])
        #expect(makeMenu().root.item(withTitle: "Awake")?.submenu != nil)
    }

    /// "Update Available…" follows Settings… only while an update waits, and opens it through Check Now.
    @Test func dropdownShowsUpdateAvailableOnlyWhenPending() {
        var pending = false
        var checks = 0
        let (menu, _) = makeMenuAndEngine(updateAvailable: { pending }, checkForUpdate: { checks += 1 })
        let plain = ["header", "-", "awake", "windows", "clipboard", "-", "settings", "quit"]
        #expect(ids(menu.root) == plain)

        pending = true
        menu.sync()
        #expect(ids(menu.root) == ["header", "-", "awake", "windows", "clipboard", "-", "settings", "updateAvailable", "quit"])
        let index = menu.root.items.firstIndex { $0.identifier?.rawValue == "updateAvailable" }!
        #expect(menu.root.items[index].title == "Update Available…")
        menu.root.performActionForItem(at: index)
        #expect(checks == 1)
        menu.sync()
        #expect(ids(menu.root).filter { $0 == "updateAvailable" }.count == 1)

        pending = false
        menu.sync()
        #expect(ids(menu.root) == plain)
    }

    @Test func awakeRowsWithTheHelperEnabled() {
        #expect(ids(makeMenu().awake) == ["on", "duration.minutes30", "duration.hour1", "duration.hours2", "duration.hours4",
            "duration.hours8", "duration.untilTurnedOff", "-", "apps", "keepScreenOn", "allowLidClose", "untilLidOpens",
            "-", "anchoredCaption", "nothingAnchored"])
    }

    @Test func lidRowsFollowHelperStatus() {
        var enabled = false
        let menu = makeMenu(helperEnabled: { enabled })
        #expect(ids(menu.awake).contains("approveLid") && !ids(menu.awake).contains("allowLidClose"))
        enabled = true
        menu.sync()
        #expect(!ids(menu.awake).contains("approveLid") && ids(menu.awake).contains("allowLidClose"))
    }

    @Test func appsItemNamesThePickedApps() async {
        let (menu, engine) = makeMenuAndEngine()
        menu.menuWillOpen(menu.root)
        engine.anchor(whileAppRuns: 999_999, appName: "Xcode")  // above macOS's pid range, so the name comes from the lease
        for _ in 0..<5 { await Task.yield() }
        let apps = menu.awake.items.first { $0.identifier?.rawValue == "apps" }!
        #expect(apps.title == "While Xcode runs" && apps.state == .on && apps.submenu === menu.apps)
        engine.release(id: "app-999999")
        for _ in 0..<5 { await Task.yield() }
        #expect(apps.title == "While an app runs…" && apps.state == .off)
    }

    @Test func pendingLeaseRowSaysWaiting() {
        let lease = Lease(id: "job", owner: .menu, reason: "r", level: .system, expiresAt: nil, createdAt: Date())
        #expect(LeaseRow.trailingText(for: lease, pending: true, now: Date()) == "waiting for your approval")
        #expect(LeaseRow.trailingText(for: lease, pending: false, now: Date()) == "Until turned off")
    }

    @Test func leaseRowsFollowTheEngineWhileOpen() async {
        let (menu, engine) = makeMenuAndEngine()
        menu.menuWillOpen(menu.root)
        engine.acquire(id: "cli", owner: .cli(pid: 4242), reason: "mooring on", level: .system, duration: nil)
        engine.acquire(id: "menu", owner: .menu, reason: "r", level: .system, duration: 600)
        for _ in 0..<5 { await Task.yield() }
        #expect(ids(menu.awake).suffix(3) == ["anchoredCaption", "lease.cli", "lease.menu"])
        engine.release(id: "cli")
        for _ in 0..<5 { await Task.yield() }
        #expect(ids(menu.awake).suffix(2) == ["anchoredCaption", "lease.menu"])
    }

    @Test func renewalKeepsTheSameRowView() async {
        let (menu, engine) = makeMenuAndEngine()
        menu.menuWillOpen(menu.root)
        engine.acquire(id: "job", owner: .cli(pid: 1), reason: "r", level: .system, duration: 600)
        for _ in 0..<5 { await Task.yield() }
        let before = menu.awake.items.first { $0.identifier?.rawValue == "lease.job" }?.view
        engine.acquire(id: "job", owner: .cli(pid: 1), reason: "r", level: .system, duration: 1200)
        for _ in 0..<5 { await Task.yield() }
        let after = menu.awake.items.first { $0.identifier?.rawValue == "lease.job" }?.view
        #expect(before != nil && before === after)
    }

    @Test func addingAndReleasingChangeOneRowEach() async {
        let (menu, engine) = makeMenuAndEngine()
        menu.menuWillOpen(menu.root)
        engine.acquire(id: "a", owner: .cli(pid: 1), reason: "r", level: .system, duration: 600)
        for _ in 0..<5 { await Task.yield() }
        let viewA = menu.awake.items.first { $0.identifier?.rawValue == "lease.a" }?.view
        engine.acquire(id: "b", owner: .cli(pid: 1), reason: "r", level: .system, duration: 600)
        for _ in 0..<5 { await Task.yield() }
        #expect(ids(menu.awake).suffix(3) == ["anchoredCaption", "lease.a", "lease.b"])
        engine.release(id: "b")
        for _ in 0..<5 { await Task.yield() }
        #expect(ids(menu.awake).suffix(2) == ["anchoredCaption", "lease.a"])
        #expect(menu.awake.items.first { $0.identifier?.rawValue == "lease.a" }?.view === viewA)
    }

    @Test func guardrailChangeLeavesLeaseRowsAlone() async {
        let (menu, engine) = makeMenuAndEngine()
        menu.menuWillOpen(menu.root)
        engine.acquire(id: "a", owner: .cli(pid: 1), reason: "r", level: AwakeLevel(display: false, lid: true), duration: 600)
        for _ in 0..<5 { await Task.yield() }
        let before = menu.awake.items.first { $0.identifier?.rawValue == "lease.a" }?.view
        engine.update(power: PowerSnapshot(onAC: false, batteryPercent: 5))
        for _ in 0..<5 { await Task.yield() }
        #expect(menu.awake.items.first { $0.identifier?.rawValue == "lease.a" }?.view === before)
    }

    @Test func appRowsAreRebuiltWhenTheSubmenuOpens() {
        var running: [NSRunningApplication] = []
        let menu = makeMenu(runningApps: { running })
        menu.menuNeedsUpdate(menu.apps)
        #expect(menu.apps.items.isEmpty)
        running = [NSRunningApplication.current]
        menu.menuNeedsUpdate(menu.apps)
        #expect(ids(menu.apps) == ["app.\(ProcessInfo.processInfo.processIdentifier)"])
    }

    @Test func highlightFollowsTheMenu() {
        let model = DropdownModel()
        let menu = makeMenu(model: model)
        menu.menuWillOpen(menu.root)
        menu.menu(menu.awake, willHighlight: menu.awake.items[2])
        #expect(model.highlightedID == "duration.hour1")
        menu.menu(menu.awake, willHighlight: nil)
        #expect(model.highlightedID == nil)
    }

    @Test func closingTheRootMenuCallsOnClose() {
        let model = DropdownModel()
        let menu = makeMenu(model: model)
        var closes = 0
        menu.onClose = { closes += 1 }
        menu.menuWillOpen(menu.root)
        menu.menuDidClose(menu.awake)
        #expect(closes == 0 && model.isOpen)
        menu.menuDidClose(menu.root)
        #expect(closes == 1 && !model.isOpen)
    }

    @Test func hostedRowsAre300PointsWide() {
        for item in makeMenu().awake.items where item.view != nil {
            #expect(item.view!.frame.width == 300)
            #expect(item.view!.frame.height > 0)
        }
    }

    /// VoiceOver reads a hosted row by its title and label, which are the row's own text, off and on.
    @Test func everyHostedRowHasATitle() async {
        let (menu, engine) = makeMenuAndEngine(runningApps: { [NSRunningApplication.current] })
        menu.menuWillOpen(menu.root)
        func expectTitled() {
            menu.menuNeedsUpdate(menu.apps)
            let menus = [menu.root, menu.awake, menu.apps, menu.windowsSubmenu.menu, menu.clipboardSubmenu.menu]
            let hosted = menus.flatMap(\.items).filter { $0.view != nil }
            #expect(hosted.count > 10)
            for item in hosted {
                let id = item.identifier?.rawValue ?? "?"
                #expect(!item.title.isEmpty, "\(id) has no title")
                #expect(item.view?.accessibilityLabel() == item.title, "\(id)'s label isn't its title")
            }
        }
        func title(_ id: String, in menu: NSMenu) -> String? {
            menu.items.first { $0.identifier?.rawValue == id }?.title
        }

        expectTitled()
        #expect(title("header", in: menu.root) == "Off")
        #expect(title("nothingAnchored", in: menu.awake) == "Nothing anchored")
        #expect(title("duration.hour1", in: menu.awake) == "For 1 h")

        engine.toggleMenu()
        engine.acquire(id: "job", owner: .cli(pid: 4242), reason: "make test", level: .system, duration: nil)
        for _ in 0..<5 { await Task.yield() }
        expectTitled()
        // The header's and a lease row's text change while the menu is open; their titles follow.
        #expect(title("header", in: menu.root) == "On · until turned off")
        #expect(title("lease.job", in: menu.awake) == "Terminal, make test, Until turned off")
    }

    @Test func actionRowsAreEnabledAfterUpdate() {
        let menu = makeMenu(runningApps: { [NSRunningApplication.current] })
        menu.menuNeedsUpdate(menu.apps)
        [menu.root, menu.awake, menu.apps].forEach { $0.update() }
        let actionIDs = ["on", "keepScreenOn", "allowLidClose", "untilLidOpens"]
        for item in menu.awake.items + menu.apps.items {
            guard let id = item.identifier?.rawValue else { continue }
            if id.hasPrefix("duration.") || id.hasPrefix("app.") || actionIDs.contains(id) {
                #expect(item.isEnabled, "\(id) should be enabled")
            }
        }
        #expect(menu.awake.items.contains { $0.identifier?.rawValue == "untilLidOpens" })
        #expect(menu.root.items.first { $0.identifier?.rawValue == "header" }?.isEnabled == false)
        #expect(menu.awake.items.first { $0.identifier?.rawValue == "anchoredCaption" }?.isEnabled == false)
    }

    @Test func headerGrowsWithItsText() {
        let (menu, engine) = makeMenuAndEngine()
        let header = menu.root.items.first { $0.identifier?.rawValue == "header" }!.view!
        let before = header.frame.height
        engine.acquire(id: "app-999999", owner: .menu, reason: "While Visual Studio Code and Microsoft Teams run",
                       level: .screenOn, duration: nil, watchPID: 999_999)
        // The hosting view only re-renders on run loop turns, even off screen.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        #expect(header.fittingSize.height > before)
        #expect(header.frame.height == before)  // the stale height the fix replaces
        menu.menuWillOpen(menu.root)
        #expect(header.frame.height == header.fittingSize.height)
        #expect(header.frame.height > before)
        #expect(header.frame.width == 300)
    }

    @Test func lidConfirmationWaitsForTheMenuToClose() async {
        var confirms = 0
        var ran = 0
        let menu = makeMenuAndEngine(needsLidConfirmation: { true }, confirmLidOnBattery: { confirms += 1 }).0
        menu.menuWillOpen(menu.root)
        menu.requestLid { ran += 1 }
        #expect(confirms == 0 && ran == 0)
        menu.menuDidClose(menu.root)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(confirms == 1 && ran == 1)
    }

    @Test func lidRequestWithoutConfirmationActsImmediately() {
        var confirms = 0
        var ran = 0
        let menu = makeMenuAndEngine(needsLidConfirmation: { false }, confirmLidOnBattery: { confirms += 1 }).0
        menu.menuWillOpen(menu.root)
        menu.requestLid { ran += 1 }
        #expect(confirms == 0 && ran == 1)
    }
}

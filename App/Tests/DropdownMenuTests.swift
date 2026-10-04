import AppKit
import AwakeKit
import Foundation
import Testing
import WindowKit
@testable import Mooring

@MainActor
struct DropdownMenuTests {
    private func ids(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : $0.identifier!.rawValue }
    }

    private func makeMenuAndEngine(
        helperEnabled: @escaping () -> Bool = { true },
        runningApps: @escaping () -> [NSRunningApplication] = { [] },
        model: DropdownModel = DropdownModel(),
        needsLidConfirmation: @escaping () -> Bool = { false },
        confirmLidOnBattery: @escaping () -> Void = {},
        windows: WindowsController? = nil,
        windowActions: WindowActions = WindowActions(menuActions: { _ in [] }, perform: { _, _ in }, frontmostPID: { nil })
    ) -> (DropdownMenu, AwakeEngine) {
        let engine = AwakeEngine(assertions: NullAssertions(), store: MemoryStore(), processes: AliveProcesses(),
                                 lid: LidController(helper: FakeLidHelper()), settings: { AwakeSettings() })
        let menu = DropdownMenu(engine: engine, model: model, helperEnabled: helperEnabled,
                                runningApps: runningApps, openSettings: {},
                                windows: windows ?? makeWindows(.off), windowActions: windowActions,
                                needsLidConfirmation: { _ in needsLidConfirmation() }, confirmLidOnBattery: confirmLidOnBattery)
        return (menu, engine)
    }

    private func makeMenu(
        helperEnabled: @escaping () -> Bool = { true },
        runningApps: @escaping () -> [NSRunningApplication] = { [] },
        model: DropdownModel = DropdownModel()
    ) -> DropdownMenu {
        makeMenuAndEngine(helperEnabled: helperEnabled, runningApps: runningApps, model: model).0
    }

    @Test func rootItemsInOrder() {
        #expect(ids(makeMenu().root) == ["header", "-", "awake", "windows", "-", "settings", "quit"])
        #expect(makeMenu().root.item(withTitle: "Awake")?.submenu != nil)
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

// MARK: Windows ›

extension DropdownMenuTests {
    private static let primary = [
        WindowMenuAction(id: "leftHalf", title: "Left Half", shortcut: "⌃⌥←", group: "Halves"),
        WindowMenuAction(id: "rightHalf", title: "Right Half", shortcut: "⌃⌥→", group: "Halves"),
        WindowMenuAction(id: "maximize", title: "Maximize", shortcut: "⌃⌥↩", group: "General"),
        WindowMenuAction(id: "center", title: "Center", shortcut: nil, group: "General"),
        WindowMenuAction(id: "nextScreen", title: "Next Screen", shortcut: nil, group: "Screen Switching")
    ]
    private static let others = [
        WindowMenuAction(id: "topHalf", title: "Top Half", shortcut: nil, group: "Halves"),
        WindowMenuAction(id: "topLeftQuarter", title: "Top Left Quarter", shortcut: nil, group: "Quarters")
    ]

    /// A real controller over fakes; `trusted` and `enabled` pick the state it reaches.
    private func makeWindows(_ state: WindowsController.State) -> WindowsController {
        let controller = WindowsController(
            trust: FakeTrust(trusted: state == .on), makeRuntime: { FakeRuntime() },
            settings: FakeSettings(enabled: state != .off), clock: FakeClock())
        controller.launch()
        #expect(controller.state == state)
        return controller
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    private func windowsMenu(
        _ state: WindowsController.State, pid: @escaping () -> pid_t? = { nil },
        calls: Calls = Calls(), hidden: Set<String> = []
    ) -> WindowsFixture {
        let windows = makeWindows(state)
        let actions = WindowActions(
            menuActions: { primary in
                calls.menuActionCalls += 1
                return (primary ? Self.primary : Self.others).filter { !hidden.contains($0.id) }
            },
            perform: { calls.performed.append(Performed(action: $0, pid: $1)) }, frontmostPID: pid)
        let (menu, _) = makeMenuAndEngine(windows: windows, windowActions: actions)
        menu.menuWillOpen(menu.root)
        return WindowsFixture(menu: menu, windows: windows, calls: calls)
    }

    struct WindowsFixture {
        let menu: DropdownMenu
        let windows: WindowsController
        let calls: Calls
    }

    struct Performed: Equatable {
        let action: String
        let pid: pid_t
    }

    final class Calls {
        var menuActionCalls = 0
        var performed: [Performed] = []
    }

    @Test func windowsOffShowsTurnOnOnly() {
        let fixture = windowsMenu(.off)
        let (menu, calls) = (fixture.menu, fixture.calls)
        #expect(ids(menu.root).contains("windows"))
        #expect(menu.root.item(withTitle: "Windows")?.submenu === menu.windowsSubmenu.menu)
        #expect(titles(menu.windowsSubmenu.menu) == ["Turn On…"])
        #expect(calls.menuActionCalls == 0)
    }

    @Test func windowsOnShowsPrimaryActionsMoreAndSwitch() {
        let menu = windowsMenu(.on).menu
        let submenu = menu.windowsSubmenu.menu
        #expect(titles(submenu) == ["Left Half", "Right Half", "Maximize", "Center", "Next Screen", "More Actions", "-", "Window Manager"])
        #expect(submenu.items.compactMap { ($0.representedObject as? WindowMenuAction)?.shortcut } == ["⌃⌥←", "⌃⌥→", "⌃⌥↩"])
        #expect(submenu.items.first { $0.title == "More Actions" }?.submenu === menu.windowsSubmenu.more)
    }

    @Test func moreActionsAreGroupedUnderDisabledHeaders() {
        let menu = windowsMenu(.on).menu
        let more = menu.windowsSubmenu.more
        menu.windowsSubmenu.menuNeedsUpdate(more)
        #expect(titles(more) == ["Halves", "Top Half", "Quarters", "Top Left Quarter"])
        #expect(more.items.filter { !$0.isEnabled }.map(\.title) == ["Halves", "Quarters"])
    }

    @Test func windowManagerSwitchTurnsWindowsOffAndOn() async {
        let fixture = windowsMenu(.on)
        let (menu, windows) = (fixture.menu, fixture.windows)
        menu.windowsSubmenu.setWindowManager(false)
        #expect(windows.state == .off)
        menu.windowsSubmenu.setWindowManager(true)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(windows.state == .on)
    }

    @Test func actionTargetsAppFrontmostBeforeOpen() {
        var frontmost: pid_t? = 111
        let fixture = windowsMenu(.on, pid: { frontmost })
        let (menu, calls) = (fixture.menu, fixture.calls)
        frontmost = 222  // Mooring or another app activated since the menu opened
        menu.windowsSubmenu.perform("leftHalf")
        #expect(calls.performed.count == 1)
        #expect(calls.performed == [Performed(action: "leftHalf", pid: 111)])
    }

    @Test func hiddenCapabilityActionsAreAbsent() {
        let menu = windowsMenu(.on, hidden: ["rightHalf", "topHalf"]).menu
        #expect(titles(menu.windowsSubmenu.menu)
            == ["Left Half", "Maximize", "Center", "Next Screen", "More Actions", "-", "Window Manager"])
        menu.windowsSubmenu.menuNeedsUpdate(menu.windowsSubmenu.more)
        #expect(titles(menu.windowsSubmenu.more) == ["Quarters", "Top Left Quarter"])
    }

    @Test func needsAccessibilityShowsReasonAndTurnOn() {
        let fixture = windowsMenu(.needsAccessibility)
        let (menu, calls) = (fixture.menu, fixture.calls)
        let submenu = menu.windowsSubmenu.menu
        #expect(titles(submenu) == ["Windows needs Accessibility", "Turn On…"])
        #expect(submenu.items[0].isEnabled == false && submenu.items[1].isEnabled)
        #expect(calls.menuActionCalls == 0)
    }

    @Test func submenuFollowsTheStateWhileOpen() async {
        let fixture = windowsMenu(.on)
        let (menu, windows) = (fixture.menu, fixture.windows)
        windows.turnOff()
        for _ in 0..<5 { await Task.yield() }
        #expect(titles(menu.windowsSubmenu.menu) == ["Turn On…"])
    }
}

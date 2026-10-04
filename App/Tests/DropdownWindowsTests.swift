import AppKit
import AwakeKit
import Foundation
import Testing
import WindowKit
@testable import Mooring

// The dropdown's Windows › submenu.
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
    func makeWindows(_ state: WindowsController.State) -> WindowsController {
        let controller = WindowsController(
            trust: FakeTrust(trusted: state == .on), makeRuntime: { FakeRuntime() },
            settings: FakeSettings(enabled: state == .on || state == .needsAccessibility), clock: FakeClock())
        if state == .waitingForTrust {
            controller.turnOn()
        } else {
            controller.launch()
        }
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
        #expect(windows.state == .off)
        menu.menuDidClose(menu.root)
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

    @Test func needsAccessibilityShowsReasonTurnOnAndTurnOff() {
        let fixture = windowsMenu(.needsAccessibility)
        let (menu, calls) = (fixture.menu, fixture.calls)
        let submenu = menu.windowsSubmenu.menu
        #expect(titles(submenu) == ["Windows needs Accessibility", "Turn On…", "Turn Off Windows"])
        #expect(submenu.items.map(\.isEnabled) == [false, true, true])
        #expect(calls.menuActionCalls == 0)
    }

    @Test func waitingForTrustShowsTurnOnAndTurnOff() {
        let fixture = windowsMenu(.waitingForTrust)
        #expect(titles(fixture.menu.windowsSubmenu.menu) == ["Turn On…", "Turn Off Windows"])
        #expect(fixture.calls.menuActionCalls == 0)
    }

    @Test func submenuFollowsTheStateWhileOpen() async {
        let fixture = windowsMenu(.on)
        let (menu, windows) = (fixture.menu, fixture.windows)
        windows.turnOff()
        for _ in 0..<5 { await Task.yield() }
        #expect(titles(menu.windowsSubmenu.menu) == ["Turn On…"])
    }

    private func standaloneSubmenu(
        _ state: WindowsController.State, calls: Calls = Calls(),
        dismiss: @escaping () -> Void = {}, afterClose: @escaping (@escaping () -> Void) -> Void = { $0() }
    ) -> (WindowsSubmenu, WindowsController) {
        let actions = WindowActions(menuActions: { _ in [] },
                                    perform: { calls.performed.append(Performed(action: $0, pid: $1)) }, frontmostPID: { 7 })
        let windows = makeWindows(state)
        let submenu = WindowsSubmenu(windows: windows, actions: actions, model: DropdownModel(), dismiss: dismiss, afterClose: afterClose)
        defer { submenu.dropdownDidOpen() }
        return (submenu, windows)
    }

    @Test func turnOnRunsAfterMenuCloses() {
        var pending: (() -> Void)?
        let (submenu, windows) = standaloneSubmenu(.off, afterClose: { pending = $0 })
        submenu.turnOn()
        #expect(windows.state == .off && pending != nil)  // the menu is still up
        pending?()  // the close callback fires; untrusted, so it waits for Accessibility
        #expect(windows.state == .waitingForTrust)
    }

    /// Turn Off Windows works from needing Accessibility, once the menu has closed.
    @Test func turnOffRunsAfterMenuCloses() {
        var pending: (() -> Void)?
        let (submenu, windows) = standaloneSubmenu(.needsAccessibility, afterClose: { pending = $0 })
        submenu.turnOff()
        #expect(windows.state == .needsAccessibility && pending != nil)
        pending?()
        #expect(windows.state == .off)
    }

    @Test func windowManagerSwitchOnWaitsForTheMenuToClose() {
        var pending: (() -> Void)?
        let (submenu, windows) = standaloneSubmenu(.off, afterClose: { pending = $0 })
        submenu.setWindowManager(true)
        #expect(windows.state == .off)
        pending?()
        #expect(windows.state == .waitingForTrust)
    }

    @Test func performDismissesThenActs() {
        let calls = Calls()
        var performedAtDismiss: Int?
        let (submenu, _) = standaloneSubmenu(.on, calls: calls, dismiss: { performedAtDismiss = calls.performed.count })
        submenu.perform("maximize")
        #expect(performedAtDismiss == 0)
        #expect(calls.performed == [Performed(action: "maximize", pid: 7)])
    }

    @Test func performIsNoOpWhenNotOn() {
        for state in [WindowsController.State.off, .needsAccessibility] {
            let calls = Calls()
            let (submenu, _) = standaloneSubmenu(state, calls: calls)
            submenu.perform("maximize")
            #expect(calls.performed.isEmpty && calls.menuActionCalls == 0)
        }
    }
}

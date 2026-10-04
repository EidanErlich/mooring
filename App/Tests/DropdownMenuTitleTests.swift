import AppKit
import AwakeKit
import Foundation
import Observation
import Testing
@testable import Mooring

/// Lease ids waiting for a lid approval, observable as `LidApprovalCenter.pending` is.
@MainActor @Observable
final class PendingLeases {
    var ids: Set<String> = []
}

/// `DropdownMenuTests` continued: the hosted rows' titles, which VoiceOver reads.
extension DropdownMenuTests {
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

    /// A lease row's title follows its lid approval while the menu is open, as the row's text does.
    @Test func leaseRowTitleFollowsPendingApproval() async {
        let pending = PendingLeases()
        let (menu, engine) = makeMenuAndEngine(pendingApproval: { pending.ids.contains($0) })
        menu.menuWillOpen(menu.root)
        engine.acquire(id: "job", owner: .cli(pid: 4242), reason: "make test", level: .system, duration: nil)
        for _ in 0..<5 { await Task.yield() }
        let row = menu.awake.items.first { $0.identifier?.rawValue == "lease.job" }
        #expect(row?.title == "Terminal, make test, Until turned off")

        pending.ids = ["job"]
        for _ in 0..<5 { await Task.yield() }
        #expect(row?.title == "Terminal, make test, waiting for your approval")
        #expect(row?.view?.accessibilityLabel() == row?.title)
        pending.ids = []
        for _ in 0..<5 { await Task.yield() }
        #expect(row?.title == "Terminal, make test, Until turned off")
    }
}

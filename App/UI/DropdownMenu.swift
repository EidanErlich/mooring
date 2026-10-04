import AppKit
import AwakeKit
import Defaults
import Observation
import SwiftUI

/// The dropdown as a real menu: native items for navigation, SwiftUI rows hosted in
/// menu items for everything live. A real menu keeps an auto-hidden menu bar shown.
@MainActor
final class DropdownMenu: NSObject, NSMenuDelegate {
    static let width: CGFloat = 300

    let root: NSMenu
    let awake = NSMenu()
    let apps = NSMenu()
    private(set) var windowsSubmenu: WindowsSubmenu!
    /// Called once when the root menu closes.
    var onClose: (() -> Void)?

    private let engine: AwakeEngine
    private let model: DropdownModel
    private let helperEnabled: () -> Bool
    private let runningApps: () -> [NSRunningApplication]
    private let openSettings: () -> Void
    private let pendingApproval: (String) -> Bool
    private let needsLidConfirmation: (PowerSnapshot) -> Bool
    private let confirmLidOnBattery: () -> Void
    private let appsItem = NSMenuItem()
    private var observing = false
    private var headerItem: NSMenuItem?
    /// An action waiting for the menu to close: a lid confirmation or Windows' Turn On.
    private var pendingAfterClose: (() -> Void)?

    init(engine: AwakeEngine, model: DropdownModel, helperEnabled: @escaping () -> Bool,
         runningApps: @escaping () -> [NSRunningApplication], openSettings: @escaping () -> Void,
         windows: WindowsController, windowActions: WindowActions = .live,
         pendingApproval: @escaping (String) -> Bool = { _ in false },
         needsLidConfirmation: @escaping (PowerSnapshot) -> Bool = { LidOptIn.needsConfirmation(power: $0, settings: Defaults[.awake]) },
         confirmLidOnBattery: @escaping () -> Void = { _ = LidOptIn.confirm() }) {
        self.engine = engine
        self.model = model
        self.helperEnabled = helperEnabled
        self.runningApps = runningApps
        self.openSettings = openSettings
        self.pendingApproval = pendingApproval
        self.needsLidConfirmation = needsLidConfirmation
        self.confirmLidOnBattery = confirmLidOnBattery
        self.root = NSMenu()
        super.init()
        windowsSubmenu = WindowsSubmenu(
            windows: windows, actions: windowActions, model: model,
            dismiss: { [weak self] in self?.root.cancelTracking() },
            afterClose: { [weak self] action in self?.runAfterClose(action) })
        for menu in [root, awake, apps] {
            menu.delegate = self
            menu.autoenablesItems = false
        }
        buildRoot()
        buildAwake()
        sync()
    }

    /// Fixes up what the hosted rows can't: the lid rows, the apps item and the lease items.
    func sync() {
        syncLidRows()
        appsItem.title = AppSessionText.rowTitle(appNames: Self.pickedAppNames(engine))
        appsItem.state = engine.sessionApps.isEmpty ? .off : .on
        syncLeaseItems()
        if let headerItem { resizeToFit(headerItem) }
    }

    /// A hosted item keeps the height it was built with, so the header (whose line can
    /// wrap or shrink as the state and leases change) is resized by hand.
    private func resizeToFit(_ item: NSMenuItem) {
        guard let view = item.view else { return }
        view.frame.size = NSSize(width: Self.width, height: view.fittingSize.height)
    }

    /// Runs a lid-mode action. On battery without the opt-in it first needs the
    /// confirmation alert, which can't run inside menu tracking, so the action waits
    /// for the menu to close.
    func requestLid(_ action: @escaping () -> Void) {
        guard needsLidConfirmation(engine.power) else {
            action()
            return
        }
        runAfterClose { [confirmLidOnBattery] in
            // "Only on AC" still turns lid mode on; the lidNeedsAC guardrail holds it until AC.
            confirmLidOnBattery()
            action()
        }
    }

    /// Cancels the menu and runs `action` from its close callback, since alerts and sheets
    /// can't run inside menu tracking.
    func runAfterClose(_ action: @escaping () -> Void) {
        pendingAfterClose = action
        root.cancelTracking()
    }

    // MARK: Delegate

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === root else { return }
        model.menuDidOpen()
        windowsSubmenu.dropdownDidOpen()
        sync()
        observe()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === root else { return }
        model.menuDidClose()
        onClose?()
        guard let action = pendingAfterClose else { return }
        pendingAfterClose = nil
        DispatchQueue.main.async(execute: action)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === apps else { return }
        apps.removeAllItems()
        for app in runningApps() {
            apps.addItem(hosted(id: "app.\(app.processIdentifier)") {
                MenuRow(title: app.localizedName ?? "App", icon: app.icon,
                        checked: Self.isPicked(self.engine, app), highlighted: self.isHighlighted("app.\(app.processIdentifier)")) {
                    Self.togglePick(self.engine, self.model, app)
                }
            })
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        model.highlightedID = item?.identifier?.rawValue
    }

    /// Arms one observation of the leases; it re-arms itself only after a change.
    private func observe() {
        guard !observing else { return }
        observing = true
        withObservationTracking {
            _ = engine.leases
            _ = engine.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                observing = false
                guard model.isOpen else { return }
                sync()
                observe()
            }
        }
    }

    // MARK: Building

    private func buildRoot() {
        let header = hosted(id: "header", enabled: false) { StatusHeader(engine: self.engine, model: self.model) }
        headerItem = header
        root.addItem(header)
        root.addItem(.separator())
        let awakeItem = NSMenuItem(title: "Awake", action: nil, keyEquivalent: "")
        awakeItem.identifier = NSUserInterfaceItemIdentifier("awake")
        awakeItem.submenu = awake
        root.addItem(awakeItem)
        let windowsItem = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
        windowsItem.identifier = NSUserInterfaceItemIdentifier("windows")
        windowsItem.submenu = windowsSubmenu.menu
        root.addItem(windowsItem)
        root.addItem(.separator())
        root.addItem(native(id: "settings", title: "Settings…", key: ",") { [openSettings] in openSettings() })
        root.addItem(native(id: "quit", title: "Quit Mooring", key: "q") { NSApp.terminate(nil) })
    }

    private func buildAwake() {
        awake.addItem(hosted(id: "on") {
            SwitchRow(title: "On", isOn: Binding(get: { self.engine.hasMenuSession }, set: { _ in self.engine.toggleMenu() }))
        })
        for duration in AwakeDuration.allCases {
            let id = "duration.\(duration)"
            awake.addItem(hosted(id: id) {
                MenuRow(title: duration.menuTitle, checked: self.model.lastPick.isChecked(duration, menuLease: self.engine.menuLease),
                        highlighted: self.isHighlighted(id)) {
                    self.engine.turnOnMenu(duration: duration.interval)
                    self.model.lastPick = DurationPick(duration: duration, expiresAt: self.engine.menuLease?.expiresAt)
                }
            })
        }
        awake.addItem(.separator())
        appsItem.identifier = NSUserInterfaceItemIdentifier("apps")
        appsItem.submenu = apps
        awake.addItem(appsItem)
        awake.addItem(hosted(id: "keepScreenOn") {
            SwitchRow(title: "Keep screen on", isOn: Binding(
                get: { self.engine.sessionLevel?.display ?? false }, set: { self.engine.setKeepScreenOn($0) }))
        })
        awake.addItem(.separator())
        awake.addItem(hosted(id: "anchoredCaption", enabled: false) {
            Text("Anchored").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
        })
    }

    private func lidItems() -> [NSMenuItem] {
        guard helperEnabled() else {
            return [native(id: "approveLid", title: "Approve lid mode…") {
                try? HelperClient.shared.register()
                HelperClient.shared.openLoginItemsSettings()
            }]
        }
        return [
            hosted(id: "allowLidClose") {
                SwitchRow(title: "Allow lid close", isOn: Binding(
                    get: { self.engine.sessionLevel?.lid ?? false },
                    set: { enabled in
                        if enabled {
                            self.requestLid { self.engine.setAllowLidClose(true) }
                        } else {
                            self.engine.setAllowLidClose(false)
                        }
                    }))
            },
            hosted(id: "untilLidOpens") {
                MenuRow(title: "Until I open the lid", highlighted: self.isHighlighted("untilLidOpens")) {
                    self.requestLid { self.engine.startLidSession() }
                }
            }
        ]
    }

    /// Replaces the lid rows when the helper's status changed since they were built.
    private func syncLidRows() {
        guard let start = index(of: "keepScreenOn", in: awake), let caption = index(of: "anchoredCaption", in: awake) else { return }
        let wanted = helperEnabled() ? ["allowLidClose", "untilLidOpens"] : ["approveLid"]
        let current = awake.items[(start + 1)..<(caption - 1)].compactMap { $0.identifier?.rawValue }
        guard current != wanted else { return }
        for _ in (start + 1)..<(caption - 1) { awake.removeItem(at: start + 1) }
        for (offset, item) in lidItems().enumerated() { awake.insertItem(item, at: start + 1 + offset) }
    }

    /// One item per lease after the caption, in engine order, or "Nothing anchored". It
    /// only adds and removes the items that changed: a renewed lease keeps its row, so a
    /// click is never delivered to a view that is about to be replaced.
    private func syncLeaseItems() {
        guard let caption = index(of: "anchoredCaption", in: awake) else { return }
        let wanted = engine.leases.map { "lease.\($0.id)" }
        let keep = Set(wanted + (wanted.isEmpty ? ["nothingAnchored"] : []))
        for item in awake.items.suffix(from: caption + 1).reversed() where !keep.contains(item.identifier?.rawValue ?? "") {
            awake.removeItem(item)
        }
        if wanted.isEmpty {
            if index(of: "nothingAnchored", in: awake) == nil {
                awake.addItem(hosted(id: "nothingAnchored", enabled: false) {
                    Text("Nothing anchored").foregroundStyle(.secondary).padding(.horizontal, 14)
                })
            }
            return
        }
        for (position, id) in wanted.enumerated() {
            let target = caption + 1 + position
            if target < awake.items.count, awake.items[target].identifier?.rawValue == id { continue }
            if let existing = awake.items.first(where: { $0.identifier?.rawValue == id }) {
                awake.removeItem(existing)
                awake.insertItem(existing, at: target)
            } else {
                let leaseID = String(id.dropFirst("lease.".count))
                let row = hosted(id: id) {
                    LeaseRow(engine: self.engine, model: self.model, id: leaseID, pendingApproval: self.pendingApproval)
                }
                awake.insertItem(row, at: target)
            }
        }
    }

    private func index(of id: String, in menu: NSMenu) -> Int? {
        menu.items.firstIndex { $0.identifier?.rawValue == id }
    }

    private func isHighlighted(_ id: String) -> Bool {
        model.highlightedID == id
    }

    /// Hosts a SwiftUI row in a menu item. The content closure runs in a view body, so
    /// whatever it reads from the engine or the model keeps the row up to date. Menus
    /// don't highlight disabled items, so only the pure-text rows are disabled.
    private func hosted(id: String, enabled: Bool = true, @ViewBuilder _ content: @escaping () -> some View) -> NSMenuItem {
        Self.hostedItem(id: id, enabled: enabled, content)
    }

    /// `title` is for accessibility and tests; the hosted view draws the row.
    static func hostedItem(id: String, title: String = "", enabled: Bool = true,
                           @ViewBuilder _ content: @escaping () -> some View) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = title
        item.isEnabled = enabled
        item.identifier = NSUserInterfaceItemIdentifier(id)
        let host = NSHostingView(rootView: LiveContent(content: content).frame(width: width, alignment: .leading))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        item.view = host
        return item
    }

    private func native(id: String, title: String, key: String = "", action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, closure: action)
        item.identifier = NSUserInterfaceItemIdentifier(id)
        return item
    }
}

// MARK: Shared behaviour

extension DropdownMenu {
    /// Names of the picked apps, from the running app when possible.
    static func pickedAppNames(_ engine: AwakeEngine) -> [String] {
        engine.sessionApps.map { lease in
            lease.watch.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName }
                ?? String(lease.reason.dropFirst("While ".count).dropLast(" runs".count))
        }
    }

    static func isPicked(_ engine: AwakeEngine, _ app: NSRunningApplication) -> Bool {
        engine.sessionApps.contains { $0.watch?.pid == app.processIdentifier }
    }

    /// Picking adds the app to the session (replacing a duration); picking again removes it.
    static func togglePick(_ engine: AwakeEngine, _ model: DropdownModel, _ app: NSRunningApplication) {
        if isPicked(engine, app) {
            engine.release(id: "app-\(app.processIdentifier)")
        } else {
            engine.anchor(whileAppRuns: app.processIdentifier, appName: app.localizedName ?? "App")
            model.lastPick = .none
        }
    }

    /// The apps a session can wait on: regular apps other than Mooring, by name.
    static func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }
}

private extension AwakeDuration {
    var menuTitle: String { self == .untilTurnedOff ? title : "For \(title)" }
}

/// Evaluates its content in its own body, so reads of observable state are tracked per row.
private struct LiveContent<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content()
    }
}

/// A native menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let closure: () -> Void

    init(title: String, keyEquivalent: String, closure: @escaping () -> Void) {
        self.closure = closure
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        closure()
    }
}

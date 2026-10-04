import AppKit
import Observation
import SwiftUI
import WindowKit

/// What the Windows submenu asks of WindowKit and the system: the real ones in the app, fakes in tests.
@MainActor
struct WindowActions {
    var menuActions: (_ primary: Bool) -> [WindowMenuAction]
    var perform: (_ actionID: String, _ pid: pid_t) -> Void
    var frontmostPID: () -> pid_t?

    static let live = WindowActions(
        menuActions: { WindowKit.menuActions(primary: $0) },
        perform: { WindowKit.perform($0, onFrontmostOf: $1) },
        frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier })
}

/// The dropdown's Windows submenu. While Windows isn't on it holds only "Turn On…" (plus the reason
/// when Accessibility is missing, and "Turn Off Windows" while it's wanted) and never asks WindowKit
/// for anything. Rows are hosted, like the Awake submenu's, so each shortcut is shown as the row's
/// trailing text rather than as a key equivalent: a menu key equivalent is a single key and would be
/// a live shortcut.
@MainActor
final class WindowsSubmenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    let more = NSMenu()

    private let windows: WindowsController
    private let actions: WindowActions
    private let model: DropdownModel
    private let dismiss: () -> Void
    /// Closes the menu, then runs the action once it has fully closed.
    private let afterClose: (_ action: @escaping () -> Void) -> Void
    /// The app that was frontmost when the dropdown opened, before Mooring could activate.
    private var targetPID: pid_t?
    private var builtFor: WindowsController.State?
    private var observing = false

    init(windows: WindowsController, actions: WindowActions, model: DropdownModel, dismiss: @escaping () -> Void,
         afterClose: @escaping (_ action: @escaping () -> Void) -> Void) {
        self.windows = windows
        self.actions = actions
        self.model = model
        self.dismiss = dismiss
        self.afterClose = afterClose
        super.init()
        for submenu in [menu, more] {
            submenu.delegate = self
            submenu.autoenablesItems = false
        }
        rebuild()
    }

    /// Called as the dropdown opens: captures the target app and brings the items up to date.
    func dropdownDidOpen() {
        targetPID = actions.frontmostPID()
        rebuild()
        observe()
    }

    func turnOn() {
        // Turning on can show the Accessibility sheet or open System Settings, so it runs from the
        // menu's close callback, never while the menu is still tracking.
        afterClose { [windows] in windows.turnOn() }
    }

    /// Turn Off Windows, offered while Windows waits for Accessibility; runs once the menu has closed.
    func turnOff() {
        afterClose { [windows] in windows.turnOff() }
    }

    func setWindowManager(_ isOn: Bool) {
        if isOn {
            turnOn()
        } else {
            windows.turnOff()
        }
    }

    func perform(_ actionID: String) {
        dismiss()
        guard windows.state == .on, let pid = targetPID else { return }
        actions.perform(actionID, pid)
    }

    // MARK: Delegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === more else { return }
        more.removeAllItems()
        guard windows.state == .on else { return }
        var seen: [String] = []
        let others = actions.menuActions(false)
        for group in others.map(\.group) where !seen.contains(group) { seen.append(group) }
        for group in seen {
            more.addItem(caption(id: "windows.more.group.\(group)", group, font: .caption.weight(.semibold)))
            for action in others where action.group == group { more.addItem(row(action, prefix: "windows.more.")) }
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        model.highlightedID = item?.identifier?.rawValue
    }

    // MARK: Building

    private func rebuild() {
        let state = windows.state
        builtFor = state
        menu.removeAllItems()
        switch state {
        case .on:
            for action in actions.menuActions(true) { menu.addItem(row(action, prefix: "windows.action.")) }
            let moreItem = NSMenuItem(title: "More Actions", action: nil, keyEquivalent: "")
            moreItem.identifier = NSUserInterfaceItemIdentifier("windows.more")
            moreItem.submenu = more
            menu.addItem(moreItem)
            menu.addItem(.separator())
            menu.addItem(DropdownMenu.hostedItem(id: "windows.manager", title: "Window Manager") {
                SwitchRow(title: "Window Manager", isOn: Binding(
                    get: { self.windows.state == .on }, set: { self.setWindowManager($0) }))
            })
        case .needsAccessibility:
            menu.addItem(caption(id: "windows.reason", "Windows needs Accessibility", font: .body))
            menu.addItem(turnOnRow())
            menu.addItem(turnOffRow())
        case .waitingForTrust:
            menu.addItem(turnOnRow())
            menu.addItem(turnOffRow())
        case .off:
            menu.addItem(turnOnRow())
        }
    }

    private func turnOnRow() -> NSMenuItem {
        DropdownMenu.hostedItem(id: "windows.turnOn", title: "Turn On…") {
            MenuRow(title: "Turn On…", highlighted: self.model.highlightedID == "windows.turnOn") { self.turnOn() }
        }
    }

    private func turnOffRow() -> NSMenuItem {
        DropdownMenu.hostedItem(id: "windows.turnOff", title: "Turn Off Windows") {
            MenuRow(title: "Turn Off Windows", highlighted: self.model.highlightedID == "windows.turnOff") { self.turnOff() }
        }
    }

    private func row(_ action: WindowMenuAction, prefix: String) -> NSMenuItem {
        let id = prefix + action.id
        let item = DropdownMenu.hostedItem(id: id, title: action.title) {
            MenuRow(title: action.title, trailing: action.shortcut, highlighted: self.model.highlightedID == id) {
                self.perform(action.id)
            }
        }
        item.representedObject = action
        return item
    }

    private func caption(id: String, _ text: String, font: Font) -> NSMenuItem {
        DropdownMenu.hostedItem(id: id, title: text, enabled: false) {
            Text(text).font(font).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 2)
        }
    }

    /// Arms one observation of the state; it re-arms itself after each change while the dropdown is open.
    private func observe() {
        guard !observing else { return }
        observing = true
        withObservationTracking {
            _ = windows.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                observing = false
                guard model.isOpen else { return }
                if windows.state != builtFor { rebuild() }
                observe()
            }
        }
    }
}

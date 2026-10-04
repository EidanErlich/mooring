import AppKit
import ClipKit
import SwiftUI

/// The dropdown's Clipboard submenu. While Clipboard is off it holds only "Turn On…" and never asks
/// ClipKit for anything. While on: the newest items, Pause Recording, Ignore Next Copy, Clear (Clear
/// All with ⌥ held as it opens) and Search…, which opens the ⇧⌘C popup. Rows are hosted, like the
/// Windows submenu's, so the ⌘-number and popup hints are trailing text rather than live key
/// equivalents.
@MainActor
final class ClipboardSubmenu: NSObject, NSMenuDelegate {
    /// What a row shows and does, kept on its menu item for tests.
    struct Row {
        let title: String
        var trailing: String?
        var checked = false
        let action: () -> Void
    }

    static let recentLimit = 10
    static let titleLimit = 50

    let menu = NSMenu()

    private let clipboard: ClipboardController
    private let model: DropdownModel
    private let dismiss: () -> Void
    /// Closes the menu, then runs the action once it has fully closed.
    private let afterClose: (_ action: @escaping () -> Void) -> Void
    private let modifierFlags: () -> NSEvent.ModifierFlags
    /// The popup hotkey as text; read only while Clipboard is on.
    private let popupShortcut: () -> String?

    init(clipboard: ClipboardController, model: DropdownModel, dismiss: @escaping () -> Void,
         afterClose: @escaping (_ action: @escaping () -> Void) -> Void,
         modifierFlags: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags },
         popupShortcut: @escaping () -> String? = { ClipKit.popupShortcutDescription }) {
        self.clipboard = clipboard
        self.model = model
        self.dismiss = dismiss
        self.afterClose = afterClose
        self.modifierFlags = modifierFlags
        self.popupShortcut = popupShortcut
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        rebuild()
    }

    /// Called as the dropdown opens.
    func dropdownDidOpen() {
        rebuild()
    }

    // MARK: Delegate

    /// Rebuilt each time it opens, so new copies show and ⌥ is read as it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rebuild()
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        model.highlightedID = item?.identifier?.rawValue
    }

    // MARK: Building

    private func rebuild() {
        menu.removeAllItems()
        guard clipboard.isOn else {
            add(id: "clipboard.turnOn", Row(title: "Turn On…") { [weak self] in
                self?.afterClose { [weak self] in self?.clipboard.turnOn() }
            })
            return
        }

        let entries = clipboard.recent(limit: Self.recentLimit)
        for (index, entry) in entries.enumerated() {
            let trailing = index < 9 ? "⌘\(index + 1)" : nil
            add(id: "clipboard.item.\(index)", Row(title: Self.menuTitle(entry.title), trailing: trailing) { [weak self] in
                self?.perform { $0.copy(entry.id) }
            })
        }
        if !entries.isEmpty { menu.addItem(.separator()) }

        let paused = clipboard.isPaused
        add(id: "clipboard.pause", Row(title: "Pause Recording", checked: paused) { [weak self] in
            self?.perform { $0.setPaused(!paused) }
        })
        add(id: "clipboard.ignoreNext", Row(title: "Ignore Next Copy") { [weak self] in
            self?.perform { $0.ignoreNextCopy() }
        })
        let all = modifierFlags().contains(.option)
        add(id: "clipboard.clear", Row(title: all ? "Clear All" : "Clear") { [weak self] in
            self?.perform { $0.clear(all: all) }
        })
        menu.addItem(.separator())
        add(id: "clipboard.search", Row(title: "Search…", trailing: popupShortcut()) { [weak self] in
            // The popup takes focus, which it can't while the menu is still tracking.
            self?.afterClose { [weak self] in self?.clipboard.showPopup() }
        })
    }

    private func perform(_ action: (ClipboardController) -> Void) {
        dismiss()
        action(clipboard)
    }

    private func add(id: String, _ row: Row) {
        let item = DropdownMenu.hostedItem(id: id, title: row.title) {
            MenuRow(title: row.title, trailing: row.trailing, checked: row.checked,
                    highlighted: self.model.highlightedID == id, action: row.action)
        }
        item.representedObject = row
        menu.addItem(item)
    }

    /// One line, at most `titleLimit` characters.
    static func menuTitle(_ title: String) -> String {
        let line = title.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard line.count > titleLimit else { return line }
        return String(line.prefix(titleLimit - 1)) + "…"
    }
}

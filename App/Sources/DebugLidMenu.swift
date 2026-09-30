#if DEBUG
import AppKit
import os

/// One row of the stage 1a debug menu (docs/SPEC.md, Engineering decisions →
/// "Stage 1a debug control"). Debug builds only; stage 1b replaces it.
enum DebugLidMenuEntry: Equatable {
    case status(HelperStatus)
    case approve
    case disableLidSleep
    case enableLidSleep
    case readSleepDisabled
    case separator
    case quit

    static func entries(for status: HelperStatus) -> [DebugLidMenuEntry] {
        var entries: [DebugLidMenuEntry] = [.status(status)]
        if status != .enabled { entries.append(.approve) }
        return entries + [.disableLidSleep, .enableLidSleep, .readSleepDisabled, .separator, .quit]
    }

    /// The flip items only work once the helper is approved, so they stay
    /// disabled until then instead of failing when clicked.
    func isEnabled(for status: HelperStatus) -> Bool {
        switch self {
        case .status, .separator: false
        case .approve, .quit: true
        case .disableLidSleep, .enableLidSleep, .readSleepDisabled: status == .enabled
        }
    }

    var title: String {
        switch self {
        case .status(let status): "Helper: \(Self.describe(status))"
        case .approve: "Approve lid mode…"
        case .disableLidSleep: "Disable lid sleep"
        case .enableLidSleep: "Enable lid sleep"
        case .readSleepDisabled: "Read SleepDisabled"
        case .separator: ""
        case .quit: "Quit Mooring"
        }
    }

    private static func describe(_ status: HelperStatus) -> String {
        switch status {
        case .notRegistered: "not registered"
        case .requiresApproval: "awaiting approval"
        case .enabled: "enabled"
        case .notFound: "not found"
        }
    }
}

/// The right-click menu that drives the helper directly, for the stage 1a spike.
@MainActor
final class DebugLidMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let helper: HelperClient
    private let log = Logger(subsystem: "dev.mooring", category: "helper")

    init(helper: HelperClient) {
        self.helper = helper
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        rebuild()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        let status = helper.status
        menu.removeAllItems()
        for entry in DebugLidMenuEntry.entries(for: status) {
            let item = makeItem(for: entry)
            item.isEnabled = entry.isEnabled(for: status)
            menu.addItem(item)
        }
    }

    private func makeItem(for entry: DebugLidMenuEntry) -> NSMenuItem {
        switch entry {
        case .separator:
            return .separator()
        case .quit:
            return NSMenuItem(title: entry.title, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        case .status:
            return NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
        case .approve, .disableLidSleep, .enableLidSleep, .readSleepDisabled:
            let item = NSMenuItem(title: entry.title, action: #selector(runEntry(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.title
            return item
        }
    }

    @objc private func runEntry(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case DebugLidMenuEntry.approve.title: approve()
        case DebugLidMenuEntry.disableLidSleep.title: flip(disabled: true)
        case DebugLidMenuEntry.enableLidSleep.title: flip(disabled: false)
        case DebugLidMenuEntry.readSleepDisabled.title: read()
        default: break
        }
    }

    private func approve() {
        do {
            try helper.register()
            helper.openLoginItemsSettings()
        } catch {
            show(error.localizedDescription)
        }
    }

    private func flip(disabled: Bool) {
        Task { @MainActor in
            do {
                try await helper.setLidSleepDisabled(disabled)
                log.notice("debug menu set SleepDisabled to \(disabled ? 1 : 0, privacy: .public)")
                show("SleepDisabled is now \(disabled ? 1 : 0)")
            } catch {
                log.error("debug menu flip failed: \(error.localizedDescription, privacy: .public)")
                show(error.localizedDescription)
            }
        }
    }

    private func read() {
        Task { @MainActor in
            do {
                let value = try await helper.lidSleepDisabled()
                let version = try await helper.version()
                show("SleepDisabled = \(value ? 1 : 0) (helper \(version))")
            } catch {
                log.error("debug menu read failed: \(error.localizedDescription, privacy: .public)")
                show(error.localizedDescription)
            }
        }
    }

    private func show(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Mooring (debug)"
        alert.informativeText = message
        alert.runModal()
    }
}
#endif

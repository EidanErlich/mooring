import AppKit
import Foundation

// MARK: - Values

/// One window. `frame` is in global points with the origin at the top left of the primary screen, as Accessibility
/// reports it.
public struct WSWindow: Sendable, Equatable {
    public var id: CGWindowID
    public var pid: pid_t
    public var title: String
    public var frame: CGRect
    public var minimized: Bool
    public var fullScreen: Bool

    public init(id: CGWindowID, pid: pid_t, title: String, frame: CGRect, minimized: Bool, fullScreen: Bool) {
        self.id = id
        self.pid = pid
        self.title = title
        self.frame = frame
        self.minimized = minimized
        self.fullScreen = fullScreen
    }
}

/// One running app with its windows, front to back.
public struct WSApp: Sendable, Equatable {
    public var name: String
    public var bundleID: String?
    public var pid: pid_t
    public var windows: [WSWindow]

    public init(name: String, bundleID: String?, pid: pid_t, windows: [WSWindow]) {
        self.name = name
        self.bundleID = bundleID
        self.pid = pid
        self.windows = windows
    }
}

/// One screen, in the same coordinates as `WSWindow.frame`. `visibleFrame` leaves out the menu bar and the Dock;
/// `isMain` marks the primary screen (the one with the menu bar).
public struct WSScreen: Sendable, Equatable {
    public var index: Int
    public var name: String
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var isMain: Bool

    public init(index: Int, name: String, frame: CGRect, visibleFrame: CGRect, isMain: Bool) {
        self.index = index
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
    }
}

// MARK: - WindowSystem

/// What arranging windows needs from the system: listing apps, windows and screens, and moving windows.
/// Calls that act return the window's frame afterwards, or nil when they couldn't act.
@MainActor
public protocol WindowSystem {
    func apps() -> [WSApp]
    /// The pids of apps with windows on screen, front to back.
    func appsFrontToBack() -> [pid_t]
    func screens() -> [WSScreen]
    /// Every region name `apply(region:to:on:)` accepts.
    func regions() -> [String]
    func frame(of window: WSWindow) -> CGRect?
    func move(_ window: WSWindow, to frame: CGRect) async -> CGRect?
    func apply(region: String, to window: WSWindow, on screen: WSScreen) async -> CGRect?
    /// The frame `apply(region:to:on:)` aims for, without moving anything; nil when it can't say ahead (screen switches).
    func target(region: String, for window: WSWindow, on screen: WSScreen) async -> CGRect?
    /// Unminimizes the window and unhides its app. Returns whether it's no longer minimized.
    func restore(_ window: WSWindow) async -> Bool
    /// Opens the app. Returns whether it launched (or was already running).
    func launch(bundleID: String) async -> Bool
    /// Shows Loop's preview overlay on `frame` briefly.
    func preview(_ frame: CGRect, on screen: WSScreen) async
}

/// How long `LiveWindowSystem` waits on the system.
enum WindowSystemTiming {
    /// The longest one Accessibility call to another app may block, in seconds. Every call runs on the main actor, so
    /// without this a hung app would stall Mooring's menu, IPC and lease renewals for the system default (about 6 s)
    /// per call, and `apps()` makes several per app.
    static let axTimeout: Float = 1.5
    /// How long Loop's preview overlay shows each target.
    static let previewDuration: Duration = .milliseconds(600)
    /// How long an app gets to unhide before its window is moved.
    static let unhideDelay: Duration = .milliseconds(150)
    /// How long the Dock's restore animation gets before the window is moved.
    static let restoreDelay: Duration = .milliseconds(350)
}

/// The real windows, through Loop's own window code. Every call does nothing (empty, nil or false) unless WindowKit
/// is running, so Windows being off means no Accessibility calls at all.
@MainActor
public final class LiveWindowSystem: WindowSystem {
    public init() {}

    private var isRunning: Bool {
        WindowKit.runningOwner != nil
    }

    /// `NSWorkspace`'s regular apps but Mooring, each with its windows from Accessibility (`kAXWindowsAttribute`) made
    /// into Loop `Window`s, which drops sheets and windows Loop can't manage. Front to back by `CGWindowList` order;
    /// minimized windows last.
    public func apps() -> [WSApp] {
        guard isRunning else { return [] }
        let order = Self.zOrder()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownPID }
            .map { app in
                let windows = Self.windowElements(pid: app.processIdentifier)
                    .compactMap { try? Window(element: $0, pid: app.processIdentifier) }
                    .map(Self.snapshot)
                    .enumerated()
                    .sorted { (order[$0.element.id] ?? .max, $0.offset) < (order[$1.element.id] ?? .max, $1.offset) }
                    .map(\.element)
                let name = app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)"
                return WSApp(name: name, bundleID: app.bundleIdentifier, pid: app.processIdentifier, windows: windows)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The owners of normal-layer windows in `CGWindowListCopyWindowInfo` order (front to back), each once.
    public func appsFrontToBack() -> [pid_t] {
        guard isRunning else { return [] }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: AnyObject]] ?? []
        var seen = Set<pid_t>()
        return list.compactMap { info -> pid_t? in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  seen.insert(pid).inserted
            else {
                return nil
            }
            return pid
        }
    }

    /// `NSScreen.screens` in order (the primary first), framed with Loop's `displayBounds` and `cgSafeScreenFrame`.
    public func screens() -> [WSScreen] {
        guard isRunning else { return [] }
        return NSScreen.screens.enumerated().map { index, screen in
            WSScreen(index: index, name: screen.localizedName, frame: screen.displayBounds,
                     visibleFrame: screen.cgSafeScreenFrame, isMain: index == 0)
        }
    }

    /// The window actions the Windows menu offers (`WindowKit.menuActions`), by region name.
    public func regions() -> [String] {
        guard isRunning else { return [] }
        return WindowRegion.offered.map(WindowRegion.name(for:))
    }

    /// Loop's `Window.frame` (the AX position and size).
    public func frame(of window: WSWindow) -> CGRect? {
        guard isRunning else { return nil }
        return loopWindow(for: window)?.frame
    }

    /// Loop's `Window.setFrame`, as its `WindowEngine.resizeWindow` does without animation: size first, then once
    /// more if the app didn't take it.
    public func move(_ window: WSWindow, to frame: CGRect) async -> CGRect? {
        guard isRunning, let target = loopWindow(for: window) else { return nil }
        await target.setFrame(frame, sizeFirst: true)
        if !target.frame.approximatelyEqual(to: frame, tolerance: 1) {
            await target.setFrame(frame)
        }
        return target.frame
    }

    /// The region's `WindowDirection` through `WindowActionEngine.shared.apply`, as the Windows menu runs it.
    public func apply(region: String, to window: WSWindow, on screen: WSScreen) async -> CGRect? {
        guard isRunning,
              let direction = WindowRegion.direction(named: region, among: WindowRegion.offered),
              let target = loopWindow(for: window),
              let nsScreen = Self.nsScreen(for: screen),
              await ActionRunner.apply(direction, to: target, on: nsScreen)
        else {
            return nil
        }
        return target.frame
    }

    /// The padded target frame of a `ResizeContext` for the region, as `WindowEngine.performResize` computes it.
    public func target(region: String, for window: WSWindow, on screen: WSScreen) async -> CGRect? {
        guard isRunning,
              let direction = WindowRegion.direction(named: region, among: WindowRegion.offered),
              !direction.willChangeScreen,
              let nsScreen = Self.nsScreen(for: screen)
        else {
            return nil
        }
        let context = ResizeContext(window: loopWindow(for: window), screen: nsScreen)
        context.setAction(to: WindowAction(direction), parent: nil)
        await context.refreshResolvedState()
        let frame = context.getTargetFrame().padded
        return frame.width > 0 && frame.height > 0 ? frame : nil
    }

    /// Loop's `Window.setHidden(false)` and `Window.minimized`.
    public func restore(_ window: WSWindow) async -> Bool {
        guard isRunning, let target = loopWindow(for: window) else { return false }
        if target.isApplicationHidden {
            target.setHidden(false)
            try? await Task.sleep(for: WindowSystemTiming.unhideDelay)
        }
        if target.minimized {
            target.minimized = false
            try? await Task.sleep(for: WindowSystemTiming.restoreDelay)
        }
        return !target.minimized
    }

    /// `NSWorkspace.openApplication`; not Loop.
    public func launch(bundleID: String) async -> Bool {
        guard isRunning, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch {
            return false
        }
    }

    /// Loop's `PreviewController`, given a custom action for exactly `frame` (`ScreenSwitchFrames.proportionalAction`)
    /// with no padding.
    public func preview(_ frame: CGRect, on screen: WSScreen) async {
        guard isRunning, let nsScreen = Self.nsScreen(for: screen) else { return }
        let bounds = nsScreen.cgSafeScreenFrame
        let context = ResizeContext(screen: nsScreen, bounds: bounds, padding: .zero,
                                    action: ScreenSwitchFrames.proportionalAction(window: frame, bounds: bounds))
        let controller = PreviewController()
        controller.open(context: context)
        try? await Task.sleep(for: WindowSystemTiming.previewDuration)
        controller.close()
    }

    // MARK: - Lookups

    /// The app's AX window elements (`kAXWindowsAttribute`), or none. The app element and each window element get
    /// `WindowSystemTiming.axTimeout`, so every later read or write through them (Loop's `Window` included) is bounded.
    private static func windowElements(pid: pid_t) -> [AXUIElement] {
        let app = bounded(AXUIElementCreateApplication(pid))
        let elements: [AXUIElement]? = try? app.getValue(.windows)
        return (elements ?? []).map(bounded)
    }

    private static func bounded(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, WindowSystemTiming.axTimeout)
        return element
    }

    /// A fresh Loop `Window` for a listed window: its app's AX window whose `_AXUIElementGetWindow` id matches.
    private func loopWindow(for window: WSWindow) -> Window? {
        guard let element = Self.windowElements(pid: window.pid).first(where: { (try? $0.getWindowID()) == window.id }) else {
            return nil
        }
        return try? Window(element: element, pid: window.pid)
    }

    private static func snapshot(_ window: Window) -> WSWindow {
        WSWindow(id: window.cgWindowID, pid: window.pid, title: window.title ?? "", frame: window.frame,
                 minimized: window.minimized, fullScreen: window.fullscreen)
    }

    /// On-screen windows' positions in `CGWindowListCopyWindowInfo`, which lists them front to back.
    private static func zOrder() -> [CGWindowID: Int] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: AnyObject]] ?? []
        var order: [CGWindowID: Int] = [:]
        for (index, info) in list.enumerated() {
            if let id = info[kCGWindowNumber as String] as? CGWindowID, order[id] == nil {
                order[id] = index
            }
        }
        return order
    }

    /// The `NSScreen` with the listed screen's display bounds, wherever it now sits in `NSScreen.screens`.
    private static func nsScreen(for screen: WSScreen) -> NSScreen? {
        NSScreen.screens.first { $0.displayBounds == screen.frame }
    }
}

// MARK: - Region names

/// A region is a `WindowDirection` by name: its raw value in kebab case ("LeftHalf" → "left-half"), with the quarters
/// shortened as SPEC writes them ("TopLeftQuarter" → "top-left"). Lookups ignore case and punctuation, and take the
/// raw value or the long quarter name too.
enum WindowRegion {
    /// The directions the Windows menu offers (so hidden features are left out), in its group order.
    @MainActor static var offered: [WindowDirection] {
        let ids = Set((WindowKit.menuActions(primary: true) + WindowKit.menuActions(primary: false)).map(\.id))
        return WindowKit.actionGroups.flatMap(\.directions).filter { ids.contains($0.rawValue) }
    }

    static func name(for direction: WindowDirection) -> String {
        var words = words(in: direction.rawValue)
        if WindowDirection.quarters.contains(direction) {
            words.removeLast()
        }
        return words.joined(separator: "-")
    }

    static func direction(named name: String, among directions: [WindowDirection]) -> WindowDirection? {
        let key = folded(name)
        guard !key.isEmpty else { return nil }
        return directions.first { folded(self.name(for: $0)) == key || folded($0.rawValue) == key }
    }

    /// "MacOSCenter" → ["mac", "os", "center"]: a word starts at a capital after a lowercase letter or digit, or at
    /// the last capital of a run that a lowercase letter follows.
    static func words(in camelCase: String) -> [String] {
        let characters = Array(camelCase)
        var words: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            if character.isUppercase, index > 0 {
                let previous = characters[index - 1]
                let nextIsLower = index + 1 < characters.count && characters[index + 1].isLowercase
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && nextIsLower) {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words.map { $0.lowercased() }
    }

    private static func folded(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

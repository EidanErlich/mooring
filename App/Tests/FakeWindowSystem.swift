import CoreGraphics
import Foundation
import WindowKit

/// A `WindowSystem` over plain values, in the same coordinates as the live one: global points, origin at the top left
/// of the main screen, so a screen left of main has negative x.
@MainActor
final class FakeWindowSystem: WindowSystem {
    var appList: [WSApp]
    var screenList: [WSScreen]
    /// Front to back; empty means `appList`'s order.
    var frontToBack: [pid_t] = []
    /// The narrowest each app's windows can be, as an app with a minimum size enforces.
    var minimumWidth: [pid_t: CGFloat] = [:]
    /// Windows whose moves fail (nil, as when Accessibility refuses).
    var failingMoves: Set<CGWindowID> = []
    /// What `launch(bundleID:)` opens, and how long until its window appears.
    var launchable: [String: (app: WSApp, delay: Duration)] = [:]
    /// Every call that acts, in order: "move 1011", "apply right-half 1011 0", "target right-half 1011 0",
    /// "restore 1021", "launch com.spotify.client", "preview 0".
    private(set) var calls: [String] = []
    /// The frames `preview` was given, in order.
    private(set) var previews: [CGRect] = []

    static let regionNames = ["left-half", "right-half", "top-half", "bottom-half", "top-left", "top-right", "bottom-left",
                              "bottom-right", "maximize", "center"]

    init(apps: [WSApp], screens: [WSScreen]) {
        appList = apps
        screenList = screens
    }

    func window(_ id: CGWindowID) -> WSWindow? {
        appList.lazy.flatMap(\.windows).first { $0.id == id }
    }

    func removeWindow(_ id: CGWindowID) {
        for index in appList.indices {
            appList[index].windows.removeAll { $0.id == id }
        }
    }

    func setFrame(_ frame: CGRect, of id: CGWindowID) {
        update(id) { $0.frame = frame }
    }

    // MARK: WindowSystem

    func apps() -> [WSApp] {
        appList
    }

    func appsFrontToBack() -> [pid_t] {
        frontToBack.isEmpty ? appList.map(\.pid) : frontToBack
    }

    func screens() -> [WSScreen] {
        screenList
    }

    func regions() -> [String] {
        Self.regionNames
    }

    func frame(of window: WSWindow) -> CGRect? {
        self.window(window.id)?.frame
    }

    func move(_ window: WSWindow, to frame: CGRect) async -> CGRect? {
        calls.append("move \(window.id)")
        return place(window, at: frame)
    }

    func apply(region: String, to window: WSWindow, on screen: WSScreen) async -> CGRect? {
        calls.append("apply \(region) \(window.id) \(screen.index)")
        guard let frame = Self.frame(of: region, current: window.frame, in: screen.visibleFrame) else { return nil }
        return place(window, at: frame)
    }

    func target(region: String, for window: WSWindow, on screen: WSScreen) async -> CGRect? {
        calls.append("target \(region) \(window.id) \(screen.index)")
        return Self.frame(of: region, current: window.frame, in: screen.visibleFrame)
    }

    func restore(_ window: WSWindow) async -> Bool {
        calls.append("restore \(window.id)")
        guard self.window(window.id) != nil else { return false }
        update(window.id) { $0.minimized = false }
        return true
    }

    func launch(bundleID: String) async -> Bool {
        calls.append("launch \(bundleID)")
        guard let entry = launchable[bundleID] else { return false }
        Task { @MainActor in
            try? await Task.sleep(for: entry.delay)
            appList.append(entry.app)
        }
        return true
    }

    func preview(_ frame: CGRect, on screen: WSScreen) async {
        calls.append("preview \(screen.index)")
        previews.append(frame)
    }

    // MARK: Helpers

    private func place(_ window: WSWindow, at frame: CGRect) -> CGRect? {
        guard self.window(window.id) != nil, !failingMoves.contains(window.id) else { return nil }
        var final = frame
        if let minimum = minimumWidth[window.pid], final.width < minimum {
            final.size.width = minimum
        }
        update(window.id) { $0.frame = final }
        return final
    }

    private func update(_ id: CGWindowID, _ change: (inout WSWindow) -> Void) {
        for appIndex in appList.indices {
            if let windowIndex = appList[appIndex].windows.firstIndex(where: { $0.id == id }) {
                change(&appList[appIndex].windows[windowIndex])
            }
        }
    }

    /// Each region as fractions of the visible area: x, y, width, height.
    private static let regionFractions: [String: [CGFloat]] = [
        "left-half": [0, 0, 0.5, 1], "right-half": [0.5, 0, 0.5, 1], "top-half": [0, 0, 1, 0.5],
        "bottom-half": [0, 0.5, 1, 0.5], "top-left": [0, 0, 0.5, 0.5], "top-right": [0.5, 0, 0.5, 0.5],
        "bottom-left": [0, 0.5, 0.5, 0.5], "bottom-right": [0.5, 0.5, 0.5, 0.5], "maximize": [0, 0, 1, 1]
    ]

    private static func frame(of region: String, current: CGRect, in area: CGRect) -> CGRect? {
        if region == "center" {
            return CGRect(x: area.midX - current.width / 2, y: area.midY - current.height / 2, width: current.width,
                          height: current.height)
        }
        guard let part = regionFractions[region] else { return nil }
        return CGRect(x: area.minX + part[0] * area.width, y: area.minY + part[1] * area.height,
                      width: part[2] * area.width, height: part[3] * area.height)
    }
}

/// Two screens (main, and a larger one to its left at negative x) and the apps `ArrangerTests` uses.
@MainActor
enum WindowFixture {
    static let main = WSScreen(index: 0, name: "Built-in Display", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                               visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875), isMain: true)
    static let left = WSScreen(index: 1, name: "Studio Display", frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080),
                               visibleFrame: CGRect(x: -1920, y: -155, width: 1920, height: 1055), isMain: false)

    static let chrome: pid_t = 101
    static let iterm: pid_t = 102
    static let slack: pid_t = 103
    static let vscode: pid_t = 104
    static let xcode: pid_t = 105
    static let keynote: pid_t = 106
    static let finder: pid_t = 107

    static let chromeInbox: CGWindowID = 1011
    static let chromeDocs: CGWindowID = 1012
    static let itermShell: CGWindowID = 1021
    static let slackMain: CGWindowID = 1031
    static let vscodeMain: CGWindowID = 1041
    static let xcodeMain: CGWindowID = 1051
    static let keynoteMain: CGWindowID = 1061
    static let finderDesktop: CGWindowID = 1071
    static let mooringSettings: CGWindowID = 1081

    static func apps() -> [WSApp] {
        let own = ProcessInfo.processInfo.processIdentifier
        return [
            app("Finder", "com.apple.finder", finder, [
                window(finderDesktop, finder, "", main.frame)
            ]),
            app("Google Chrome", "com.google.Chrome", chrome, [
                window(chromeInbox, chrome, "Inbox – Mail – Google", CGRect(x: 100, y: 100, width: 800, height: 600)),
                window(chromeDocs, chrome, "Docs – Google", CGRect(x: 200, y: 150, width: 800, height: 600))
            ]),
            app("iTerm2", "com.googlecode.iterm2", iterm, [
                window(itermShell, iterm, "zsh", CGRect(x: 300, y: 300, width: 700, height: 400), minimized: true)
            ]),
            app("Keynote", "com.apple.iWork.Keynote", keynote, [
                window(keynoteMain, keynote, "Talk", main.frame, fullScreen: true)
            ]),
            app("Mooring", "dev.mooring.app", own, [
                window(mooringSettings, own, "Mooring Settings", CGRect(x: 400, y: 200, width: 600, height: 400))
            ]),
            app("Slack", "com.tinyspeck.slackmacgap", slack, [
                window(slackMain, slack, "Slack – General", CGRect(x: -1800, y: -100, width: 1000, height: 700))
            ]),
            app("Visual Studio Code", "com.microsoft.VSCode", vscode, [
                window(vscodeMain, vscode, "Arranger.swift", CGRect(x: 50, y: 60, width: 1200, height: 800))
            ]),
            app("Xcode", "com.apple.dt.Xcode", xcode, [
                window(xcodeMain, xcode, "Mooring", CGRect(x: -1700, y: 0, width: 1400, height: 900))
            ])
        ]
    }

    static func system(screens: [WSScreen] = [main, left]) -> FakeWindowSystem {
        FakeWindowSystem(apps: apps(), screens: screens)
    }

    static func app(_ name: String, _ bundleID: String?, _ pid: pid_t, _ windows: [WSWindow]) -> WSApp {
        WSApp(name: name, bundleID: bundleID, pid: pid, windows: windows)
    }

    static func window(_ id: CGWindowID, _ pid: pid_t, _ title: String, _ frame: CGRect, minimized: Bool = false,
                       fullScreen: Bool = false) -> WSWindow {
        WSWindow(id: id, pid: pid, title: title, frame: frame, minimized: minimized, fullScreen: fullScreen)
    }
}

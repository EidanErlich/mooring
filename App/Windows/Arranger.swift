import CoreGraphics
import Foundation
import MooringIPC
import WindowKit

/// Arranges windows from a `WinPlan` over a `WindowSystem`: matches each placement to one window, resolves every
/// placement before moving anything, then applies them in plan order and reports one result each. Keeps the last
/// `maxUndo` arrangements that moved something, and the saved layouts (`Layouts.swift`).
/// Coordinates are `WindowSystem`'s (see `ScreenPicker`).
@MainActor
final class Arranger {
    /// A moved window's frame before the arrangement.
    struct UndoEntry: Equatable {
        let app: String
        let pid: pid_t
        let windowID: CGWindowID
        let frame: CGRect
    }

    /// Final frames within this many points of the target, in width and height, count as `ok`.
    static let sizeTolerance: CGFloat = 2

    let system: any WindowSystem
    let layouts: LayoutStore
    private let maxUndo: Int
    private let ownPID: pid_t
    private let locateApp: @MainActor (String) -> String?
    /// A saved layout's `app`, a bundle id, as the ask names it.
    let appName: @MainActor (String) -> String
    private let launchTimeout: Duration
    private let pollInterval: Duration
    private var undoStack: [[UndoEntry]] = []

    /// `locateApp` turns a query for an app that isn't running into a bundle id to open; `appName` turns a bundle id
    /// into the app's name, or gives it back; `launchTimeout` is how long an opened app gets to show a window.
    init(system: any WindowSystem, layoutsURL: URL, maxUndo: Int = 10,
         ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
         locateApp: @escaping @MainActor (String) -> String? = AppLocator.bundleID(for:),
         appName: @escaping @MainActor (String) -> String = AppLocator.displayName(for:),
         launchTimeout: Duration = .seconds(10), pollInterval: Duration = .milliseconds(200)) {
        self.system = system
        layouts = LayoutStore(url: layoutsURL)
        self.maxUndo = maxUndo
        self.ownPID = ownPID
        self.locateApp = locateApp
        self.appName = appName
        self.launchTimeout = launchTimeout
        self.pollInterval = pollInterval
    }

    /// The system's apps but Mooring.
    func visibleApps() -> [WSApp] {
        system.apps().filter { $0.pid != ownPID }
    }

    func list() -> WinListResult {
        let screens = system.screens()
        let positions = ScreenPicker.positions(of: screens)
        let apps = visibleApps().map { app in
            WinAppInfo(name: app.name, bundleID: app.bundleID, pid: app.pid, windows: app.windows.map { window in
                WinWindowInfo(id: window.id, title: window.title, frame: WinFrame(window.frame),
                              screen: ScreenPicker.screen(containing: window.frame, in: screens)?.index ?? 0,
                              minimized: window.minimized, fullScreen: window.fullScreen)
            })
        }
        return WinListResult(
            apps: apps,
            screens: screens.map {
                WinScreenInfo(index: $0.index, name: $0.name, visibleFrame: WinFrame($0.visibleFrame),
                              position: positions[$0.index] ?? "other")
            },
            regions: system.regions())
    }

    func arrange(_ plan: WinPlan) async -> WinArrangeResult {
        var results: [WinPlacementResult] = []
        var moved: [UndoEntry] = []
        for (placement, step) in zip(plan.placements, await resolve(plan)) {
            switch step {
            case .done(let result):
                results.append(result)
            case .launch:
                results.append(WinPlacementResult(app: placement.app, status: .notRunning, reason: "couldn't open it"))
            case .target(let target):
                let (result, entry) = await place(target, preview: plan.preview == true)
                results.append(result)
                if let entry, !moved.contains(where: { $0.windowID == entry.windowID }) {
                    moved.append(entry)
                }
            }
        }
        if !moved.isEmpty {
            undoStack.append(moved)
            undoStack.removeFirst(max(undoStack.count - maxUndo, 0))
        }
        return WinArrangeResult(results: results, undoAvailable: !undoStack.isEmpty)
    }

    /// One region on one window: the named app's frontmost window, or the frontmost app's.
    func perform(region: String, app: String?, screen: String?) async -> WinArrangeResult {
        await arrange(WinPlan(placements: [WinPlacement(app: app ?? WinPlacement.frontmostApp, region: region, screen: screen)]))
    }

    /// Moves each window of the latest arrangement back. A window that's gone is skipped and reported `not_found`.
    func undo() async -> WinArrangeResult? {
        guard let entries = undoStack.popLast() else { return nil }
        let windows = visibleApps().flatMap(\.windows)
        var results: [WinPlacementResult] = []
        for entry in entries {
            guard let window = windows.first(where: { $0.id == entry.windowID && $0.pid == entry.pid }) else {
                results.append(WinPlacementResult(app: entry.app, status: .notFound, reason: "the window is gone"))
                continue
            }
            guard let final = await system.move(window, to: entry.frame) else {
                results.append(WinPlacementResult(app: entry.app, status: .failed, reason: "couldn't move the window"))
                continue
            }
            results.append(WinPlacementResult(app: entry.app, status: Self.status(final, aimingAt: entry.frame),
                                              frame: WinFrame(final)))
        }
        return WinArrangeResult(results: results, undoAvailable: !undoStack.isEmpty)
    }
}

// MARK: - Resolving

extension Arranger {
    private enum Goal {
        case region(String)
        case frame(CGRect)
    }

    private struct Target {
        let label: String
        let window: WSWindow
        let screen: WSScreen
        let goal: Goal
        let note: String?
    }

    private enum Step {
        case done(WinPlacementResult)
        case target(Target)
        /// Not running yet: open it first.
        case launch(bundleID: String)
    }

    private struct Refusal: Error {
        let result: WinPlacementResult
    }

    /// Every placement, matched against the apps as they are now; then, if the plan launches, the apps that weren't
    /// running are opened, waited for, and matched by bundle id.
    private func resolve(_ plan: WinPlan) async -> [Step] {
        let screens = system.screens()
        let running = visibleApps()
        var steps = plan.placements.map { step(for: $0, apps: running, screens: screens, canLaunch: plan.launch == true) }
        var toLaunch: [String] = []
        for case .launch(let bundleID) in steps where !toLaunch.contains(bundleID) {
            toLaunch.append(bundleID)
        }
        guard !toLaunch.isEmpty else { return steps }

        let opened = await open(toLaunch)
        let apps = visibleApps()
        for index in steps.indices {
            guard case .launch(let bundleID) = steps[index] else { continue }
            let label = plan.placements[index].app
            guard opened.contains(bundleID) else {
                steps[index] = .done(WinPlacementResult(app: label, status: .notRunning, reason: "couldn't open it"))
                continue
            }
            guard let app = apps.first(where: { $0.bundleID?.lowercased() == bundleID.lowercased() }) else {
                steps[index] = .done(WinPlacementResult(app: label, status: .notRunning, reason: "didn't open in time"))
                continue
            }
            steps[index] = step(for: plan.placements[index], in: app, screens: screens, note: "launched")
        }
        return steps
    }

    private func step(for placement: WinPlacement, apps: [WSApp], screens: [WSScreen], canLaunch: Bool) -> Step {
        let label = placement.app
        if placement.app == WinPlacement.frontmostApp {
            guard let app = frontmostApp(in: apps) else {
                return .done(WinPlacementResult(app: label, status: .notFound, reason: "no app is in front"))
            }
            return step(for: placement, in: app, screens: screens, note: nil)
        }
        switch AppMatcher.match(placement.app, in: apps) {
        case .one(let app):
            return step(for: placement, in: app, screens: screens, note: nil)
        case .ambiguous(let apps):
            return .done(Self.ambiguous(label, apps.map(\.name), several: "apps"))
        case .none:
            guard canLaunch else { return .done(WinPlacementResult(app: label, status: .notRunning, reason: "isn't running")) }
            guard let bundleID = locateApp(placement.app) else {
                return .done(WinPlacementResult(app: label, status: .notRunning, reason: "couldn't find it to open"))
            }
            return .launch(bundleID: bundleID)
        }
    }

    private func step(for placement: WinPlacement, in app: WSApp, screens: [WSScreen], note: String?) -> Step {
        let label = placement.app
        do {
            let window = try Self.window(for: placement, in: app)
            guard !window.fullScreen else { throw Refusal(result: .init(app: label, status: .failed, reason: "is full screen")) }
            let screen: WSScreen
            switch ScreenPicker.pick(placement.screen, for: window.frame, in: screens) {
            case .success(let picked): screen = picked
            case .failure(let failure): throw Refusal(result: .init(app: label, status: .failed, reason: failure.reason))
            }
            let goal: Goal
            if let frame = placement.frame {
                goal = .frame(ScreenPicker.rect(frame, in: screen.visibleFrame))
            } else {
                let region = placement.region ?? ""
                guard let name = regionName(region) else {
                    let reason = system.isWithheld(region: region) ? "region isn't available to agents" : "unknown region “\(region)”"
                    throw Refusal(result: .init(app: label, status: .failed, reason: reason))
                }
                goal = .region(name)
            }
            return .target(Target(label: label, window: window, screen: screen, goal: goal, note: note))
        } catch let refusal as Refusal {
            return .done(refusal.result)
        } catch {
            return .done(WinPlacementResult(app: label, status: .failed, reason: "\(error)"))
        }
    }

    /// The window titled exactly `title` (any case), else the one whose title contains it; two or more at the tier that
    /// decides is ambiguous. With no title, the app's frontmost window.
    private static func window(for placement: WinPlacement, in app: WSApp) throws -> WSWindow {
        let label = placement.app
        guard let title = placement.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            guard let frontmost = app.windows.first else {
                throw Refusal(result: .init(app: label, status: .notFound, reason: "has no windows"))
            }
            return frontmost
        }
        let exact = app.windows.filter { $0.title.caseInsensitiveCompare(title) == .orderedSame }
        let matches = exact.isEmpty ? app.windows.filter { $0.title.range(of: title, options: .caseInsensitive) != nil } : exact
        guard matches.count < 2 else {
            throw Refusal(result: ambiguous(label, matches.map(\.title), several: "windows"))
        }
        guard let match = matches.first else {
            throw Refusal(result: .init(app: label, status: .notFound, reason: "no window titled “\(title)”"))
        }
        return match
    }

    /// "matches several apps: Visual Studio Code, Xcode", so the agent knows whether to refine `app` or `title`.
    private static func ambiguous(_ label: String, _ names: [String], several kind: String) -> WinPlacementResult {
        WinPlacementResult(app: label, status: .ambiguous, candidates: names,
                           reason: "matches several \(kind): \(names.joined(separator: ", "))")
    }

    /// The first app in the system's front-to-back order that isn't Mooring.
    private func frontmostApp(in apps: [WSApp]) -> WSApp? {
        for pid in system.appsFrontToBack() where pid != ownPID {
            if let app = apps.first(where: { $0.pid == pid }) {
                return app
            }
        }
        return nil
    }

    /// The system's own spelling of a region, ignoring case and punctuation.
    private func regionName(_ region: String) -> String? {
        let key = Self.folded(region)
        guard !key.isEmpty else { return nil }
        return system.regions().first { Self.folded($0) == key }
    }

    private static func folded(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

}

// MARK: - Applying

extension Arranger {
    /// Restores a minimized window, previews the target if asked, then moves the window there.
    private func place(_ target: Target, preview: Bool) async -> (WinPlacementResult, UndoEntry?) {
        let window = target.window
        var notes = target.note.map { [$0] } ?? []
        func failure(_ reason: String) -> (WinPlacementResult, UndoEntry?) {
            (WinPlacementResult(app: target.label, status: .failed, reason: reason, note: Self.joined(notes)), nil)
        }

        if window.minimized {
            guard await system.restore(window) else { return failure("couldn't restore it") }
            notes.append("was minimized, restored")
        }
        let previous = system.frame(of: window) ?? window.frame
        let aim: CGRect?
        switch target.goal {
        case .frame(let frame): aim = frame
        case .region(let region): aim = await system.target(region: region, for: window, on: target.screen)
        }
        if preview, let aim {
            await system.preview(aim, on: target.screen)
        }
        let final: CGRect?
        switch target.goal {
        case .frame(let frame): final = await system.move(window, to: frame)
        case .region(let region): final = await system.apply(region: region, to: window, on: target.screen)
        }
        guard let final else { return failure("couldn't move the window") }

        let status = aim.map { Self.status(final, aimingAt: $0) } ?? .ok
        let result = WinPlacementResult(app: target.label, status: status, frame: WinFrame(final), note: Self.joined(notes))
        return (result, UndoEntry(app: target.label, pid: window.pid, windowID: window.id, frame: previous))
    }

    /// `partial` when the app kept the window more than `sizeTolerance` away from the target's size.
    private static func status(_ final: CGRect, aimingAt target: CGRect) -> WinStatus {
        let off = abs(final.width - target.width) > sizeTolerance || abs(final.height - target.height) > sizeTolerance
        return off ? .partial : .ok
    }

    private static func joined(_ notes: [String]) -> String? {
        notes.isEmpty ? nil : notes.joined(separator: "; ")
    }

    /// Opens each app, then waits up to `launchTimeout` for every opened one to show a window. Returns those that
    /// opened.
    private func open(_ bundleIDs: [String]) async -> Set<String> {
        var opened = Set<String>()
        for bundleID in bundleIDs {
            let launched = await system.launch(bundleID: bundleID)
            if launched {
                opened.insert(bundleID)
            }
        }
        guard !opened.isEmpty else { return opened }
        let deadline = ContinuousClock.now.advanced(by: launchTimeout)
        while ContinuousClock.now < deadline {
            let apps = visibleApps()
            let ready = opened.allSatisfy { bundleID in
                apps.contains { $0.bundleID?.lowercased() == bundleID.lowercased() && !$0.windows.isEmpty }
            }
            if ready {
                break
            }
            try? await Task.sleep(for: pollInterval)
        }
        return opened
    }
}

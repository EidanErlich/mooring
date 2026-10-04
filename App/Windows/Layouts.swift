import CoreGraphics
import Foundation
import MooringIPC
import WindowKit

/// Saved layouts in `layouts.json`: `{ "<name>": [WinPlacement] }`, each placement a bundle-id `app`, a screen index
/// and a `frame` of screen fractions.
struct LayoutStore {
    let url: URL

    /// `~/Library/Application Support/Mooring/layouts.json`.
    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Mooring", isDirectory: true).appendingPathComponent("layouts.json")
    }

    /// The saved layouts; none when the file doesn't exist yet.
    func load() throws -> [String: [WinPlacement]] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            return try JSONDecoder().decode([String: [WinPlacement]].self, from: Data(contentsOf: url))
        } catch {
            throw WireError(code: .internal, message: "Couldn't read saved layouts: \(error.localizedDescription)")
        }
    }

    func save(_ layouts: [String: [WinPlacement]]) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(layouts).write(to: url, options: .atomic)
        } catch {
            throw WireError(code: .internal, message: "Couldn't save layouts: \(error.localizedDescription)")
        }
    }
}

extension Arranger {
    /// `win.layout`: `save` captures the screens as they are, `apply` arranges a saved layout with `launch` on,
    /// `list` gives the names, and `delete` removes one.
    func layout(_ args: WinLayoutArgs) async throws -> WinLayoutResult {
        var saved = try layouts.load()
        switch args.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "list":
            return WinLayoutResult(names: saved.keys.sorted(), arrange: nil)
        case "save":
            let name = try Self.layoutName(args)
            let placements = LayoutCapture.placements(apps: visibleApps(), screens: system.screens())
            guard !placements.isEmpty else { throw WireError(code: .badRequest, message: "No windows to save") }
            saved[name] = placements
            try layouts.save(saved)
            return WinLayoutResult(names: saved.keys.sorted(), arrange: nil)
        case "apply":
            let name = try Self.layoutName(args)
            guard let placements = saved[name] else { throw Self.noLayout(name) }
            let checked = try Self.validated(layout: placements, named: name)
            return WinLayoutResult(names: saved.keys.sorted(), arrange: await apply(layout: checked))
        case "delete":
            let name = try Self.layoutName(args)
            guard saved.removeValue(forKey: name) != nil else { throw Self.noLayout(name) }
            try layouts.save(saved)
            return WinLayoutResult(names: saved.keys.sorted(), arrange: nil)
        default:
            throw WireError(code: .badRequest,
                            message: "Unknown layout action “\(args.action)” (use save, apply, list or delete)")
        }
    }

    /// Arranges a saved layout's placements, opening apps that aren't running.
    func apply(layout placements: [WinPlacement]) async -> WinArrangeResult {
        await arrange(WinPlan(placements: placements, launch: true))
    }

    /// A saved layout's placements checked as any plan (`WinPlan.validated()`: at most 32, frames clamped), since the
    /// file can be edited by hand; `bad_request` "Layout <name> is invalid: …" otherwise.
    static func validated(layout placements: [WinPlacement], named name: String) throws -> [WinPlacement] {
        do {
            return try WinPlan(placements: placements, launch: true).validated().placements
        } catch let error as WireError {
            throw WireError(code: .badRequest, message: "Layout \(name) is invalid: \(error.message)")
        }
    }

    private static func layoutName(_ args: WinLayoutArgs) throws -> String {
        let name = args.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { throw WireError(code: .badRequest, message: "Give the layout a name") }
        return name
    }

    private static func noLayout(_ name: String) -> WireError {
        WireError(code: .notFound, message: "No layout named \(name)")
    }
}

/// What `save` keeps: on each screen, the frontmost window of each app, as fractions of that screen's visible area.
enum LayoutCapture {
    static let finder = "com.apple.finder"

    private struct Pick {
        let app: WSApp
        let window: WSWindow
        let screen: WSScreen
    }

    /// At most `WinPlan.maxPlacements`, main screen first. Leaves out minimized and full-screen windows and Finder's
    /// desktop window. An app with windows on more than one screen gets each window's title, so `apply` can tell them
    /// apart; otherwise the title is left out, and `apply` takes the app's frontmost window.
    static func placements(apps: [WSApp], screens: [WSScreen]) -> [WinPlacement] {
        let ordered = screens.sorted { ($0.isMain ? 0 : 1, $0.index) < ($1.isMain ? 0 : 1, $1.index) }
        var picked: [Pick] = []
        for screen in ordered {
            for app in apps {
                let window = app.windows.first { window in
                    isSaved(window, of: app, screens: screens)
                        && ScreenPicker.screen(containing: window.frame, in: screens)?.index == screen.index
                }
                if let window {
                    picked.append(Pick(app: app, window: window, screen: screen))
                }
            }
        }
        let placements = picked.map { entry in
            let shared = picked.filter { $0.app.pid == entry.app.pid }.count > 1
            return WinPlacement(app: entry.app.bundleID ?? entry.app.name,
                                frame: ScreenPicker.fraction(entry.window.frame, in: entry.screen.visibleFrame),
                                screen: String(entry.screen.index),
                                title: shared && !entry.window.title.isEmpty ? entry.window.title : nil)
        }
        return Array(placements.prefix(WinPlan.maxPlacements))
    }

    private static func isSaved(_ window: WSWindow, of app: WSApp, screens: [WSScreen]) -> Bool {
        !window.minimized && !window.fullScreen && !isDesktop(window, of: app, screens: screens)
    }

    /// Finder's desktop: untitled and the size of a whole screen.
    private static func isDesktop(_ window: WSWindow, of app: WSApp, screens: [WSScreen]) -> Bool {
        app.bundleID == finder && window.title.isEmpty && screens.contains { screen in
            abs(screen.frame.width - window.frame.width) <= 2 && abs(screen.frame.height - window.frame.height) <= 2
        }
    }
}

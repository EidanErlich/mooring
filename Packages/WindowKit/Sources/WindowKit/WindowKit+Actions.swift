import AppKit
import Defaults
import Foundation
import os

public struct WindowMenuAction: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let shortcut: String?
    public let group: String
}

public struct WindowKeybind: Equatable, Sendable {
    public let title: String
    public let chord: String
}

extension WindowDirection {
    /// Actions that stand on their own; custom frames and cycles need a configured keybind.
    var isMenuAction: Bool {
        ![.noAction, .noSelection, .custom, .cycle].contains(self)
    }
}

// MARK: - Menu actions and keybinds (static data and Defaults only; no managers)

extension WindowKit {
    static let primaryDirections: [WindowDirection] = [.leftHalf, .rightHalf, .maximize, .center, .nextScreen]

    /// Loop's own action groups (the Keybinds tab's action picker), without Focus and Stash, which stay
    /// hidden in 3a. Loop lists numbered spaces up to the desktop count, which needs SkyLight, so
    /// only next and previous space are listed here.
    static let actionGroups: [(title: String, directions: [WindowDirection])] = [
        ("General", WindowDirection.general),
        ("Halves", WindowDirection.halves),
        ("Quarters", WindowDirection.quarters),
        ("Horizontal Thirds", WindowDirection.horizontalThirds),
        ("Vertical Thirds", WindowDirection.verticalThirds),
        ("Horizontal Fourths", WindowDirection.horizontalFourths),
        ("Screen Switching", WindowDirection.screenSwitching),
        ("Space Switching", WindowDirection.relativeSpaceSwitching),
        ("Size Adjustment", WindowDirection.sizeAdjustment),
        ("Shrink", WindowDirection.shrink),
        ("Grow", WindowDirection.grow),
        ("Move", WindowDirection.move),
        ("Go Back", [.initialFrame, .undo])
    ]

    /// `primary: true` gives the dropdown's five actions; `false` gives the rest, in Loop's groups.
    /// Actions whose private-API feature failed are left out of both.
    public static func menuActions(primary: Bool) -> [WindowMenuAction] {
        let hidden = Capabilities.active.hidden
        let shortcuts = shortcutsByDirection()
        let groups = actionGroups.flatMap { group in
            group.directions.map { (direction: $0, group: group.title) }
        }
        let primarySet = Set(primaryDirections)

        let chosen = if primary {
            primaryDirections.compactMap { direction in groups.first { $0.direction == direction } }
        } else {
            groups.filter { !primarySet.contains($0.direction) }
        }

        return chosen
            .filter { !hidden.contains($0.direction.rawValue) }
            .map { item in
                WindowMenuAction(
                    id: item.direction.rawValue,
                    title: item.direction.name,
                    shortcut: shortcuts[item.direction],
                    group: item.group
                )
            }
    }

    /// The trigger key first, then each bound Loop keybind, with chords from `WindowChord`.
    public static func keybinds() -> [WindowKeybind] {
        let trigger = Defaults[.triggerKey]
        let bound = Defaults[.keybinds]
            .filter { !$0.keybind.isEmpty }
            .map { WindowKeybind(title: $0.getName(), chord: chord(for: $0, trigger: trigger)) }
        return [WindowKeybind(title: "Trigger Key", chord: WindowChord.format(trigger))] + bound
    }

    private static func chord(for action: WindowAction, trigger: Set<CGKeyCode>) -> String {
        let keys = action.bypassTriggerKey == true ? action.keybind : action.keybind.union(trigger)
        return WindowChord.format(keys)
    }

    /// A direction's own keybind, or else a cycle's that starts with it (pressing it once gives that action).
    private static func shortcutsByDirection() -> [WindowDirection: String] {
        let trigger = Defaults[.triggerKey]
        var result: [WindowDirection: String] = [:]
        let bound = Defaults[.keybinds].filter { !$0.keybind.isEmpty }

        for action in bound where action.direction != .cycle && result[action.direction] == nil {
            result[action.direction] = chord(for: action, trigger: trigger)
        }
        for action in bound where action.direction == .cycle {
            if let first = action.cycle?.first?.direction, result[first] == nil {
                result[first] = chord(for: action, trigger: trigger)
            }
        }
        return result
    }
}

// MARK: - Performing an action

extension WindowKit {
    private static let logger = Logger(subsystem: "dev.mooring", category: "windows")

    /// Applies an offered action to the focused window of `pid`. Unknown, hidden or not-offered ids,
    /// and any call while WindowKit is stopped, do nothing.
    public static func perform(_ actionID: String, onFrontmostOf pid: pid_t) {
        guard runningOwner != nil, let direction = performableDirection(actionID) else {
            logger.debug("Windows: ignored action \(actionID, privacy: .public)")
            return
        }

        Task {
            await ActionRunner.run(direction, pid: pid)
        }
    }

    static func performableDirection(_ actionID: String) -> WindowDirection? {
        let offered = (menuActions(primary: true) + menuActions(primary: false)).map(\.id)
        guard offered.contains(actionID) else { return nil }
        return WindowDirection(rawValue: actionID)
    }
}

@MainActor
private enum ActionRunner {
    static func run(_ direction: WindowDirection, pid: pid_t) async {
        guard let window = try? Window(pid: pid),
              let screen = ScreenUtility.screenContaining(window)
        else {
            return
        }

        if direction.willChangeScreen {
            guard let target = targetScreen(for: direction, from: screen) else { return }
            let action = await screenSwitchAction(for: window, on: screen)
            _ = try? await WindowActionEngine.shared.apply(action, window: window, screen: target)
        } else {
            _ = try? await WindowActionEngine.shared.apply(WindowAction(direction), window: window, screen: screen)
        }
    }

    private static func targetScreen(for direction: WindowDirection, from screen: NSScreen) -> NSScreen? {
        switch direction {
        case .nextScreen: ScreenUtility.nextScreen(from: screen)
        case .previousScreen: ScreenUtility.previousScreen(from: screen)
        case .leftScreen: ScreenUtility.directionalScreen(from: screen, direction: .left)
        case .rightScreen: ScreenUtility.directionalScreen(from: screen, direction: .right)
        case .topScreen: ScreenUtility.directionalScreen(from: screen, direction: .top)
        case .bottomScreen: ScreenUtility.directionalScreen(from: screen, direction: .bottom)
        default: nil
        }
    }

    /// As Loop's `LoopManager` does: repeat the window's last Loop action on the new screen, or else
    /// keep its frame in proportion to the screen.
    private static func screenSwitchAction(for window: Window, on screen: NSScreen) async -> WindowAction {
        if let last = await WindowRecords.shared.getCurrentAction(for: window),
           last.getName() != ScreenSwitchFrames.autogeneratedName,
           !last.forceProportionalFrameOnScreenChange {
            return last
        }

        let bounds = PaddingConfiguration
            .getConfiguredPadding(for: screen)
            .applyToBounds(screen.cgSafeScreenFrame, screen: screen)
        return ScreenSwitchFrames.proportionalAction(window: window.frame, bounds: bounds)
    }
}

// Adapted from Loop@0ac6d83: Loop/Extensions/Defaults+Extensions.swift
//
//  Defaults+Extensions.swift
//  Loop
//
//  Created by Kai Azim on 2023-06-14.
//
// NOTE: While iCloud is enabled, its service is currently disabled to make GitHub actions work.

import Defaults
import Scribe
import SwiftUI

// MARK: - UI-configurable Settings

extension Defaults.Keys {
    // Icon
    static let currentIcon = Key<String>("currentIcon", default: "AppIcon-Classic", suite: .windowKit, iCloud: false)
    static let timesLooped = Key<Int>("timesLooped", default: 0, suite: .windowKit, iCloud: false)
    static let showDockIcon = Key<Bool>("showDockIcon", default: false, suite: .windowKit, iCloud: false)
    static let notificationWhenIconUnlocked = Key<Bool>("notificationWhenIconUnlocked", default: true, suite: .windowKit, iCloud: false)

    // Accent Color
    static let accentColorMode: Key<AccentColorOption> = Key("accentColorMode", default: .system, suite: .windowKit, iCloud: false)
    static let customAccentColor = Key<Color>("customAccentColor", default: .teal, suite: .windowKit, iCloud: false)
    static let useGradient = Key<Bool>("useGradient", default: false, suite: .windowKit, iCloud: false)
    static let gradientColor = Key<Color>("gradientColor", default: .blue, suite: .windowKit, iCloud: false)

    // Radial Menu
    static let radialMenuVisibility = Key<Bool>("radialMenuVisibility", default: true, suite: .windowKit, iCloud: false)
    static let radialMenuCornerRadius = Key<CGFloat>("radialMenuCornerRadius", default: 50, suite: .windowKit, iCloud: false)
    static let radialMenuThickness = Key<CGFloat>("radialMenuThickness", default: 22, suite: .windowKit, iCloud: false)
    static let radialMenuActions = Key<[RadialMenuAction]>("radialMenuActions", default: RadialMenuAction.defaultRadialMenuActions, suite: .windowKit, iCloud: false)

    // Preview
    static let previewVisibility = Key<Bool>("previewVisibility", default: true, suite: .windowKit, iCloud: false)
    static let previewPadding = Key<CGFloat>("previewPadding", default: 10, suite: .windowKit, iCloud: false)
    static let previewCornerRadius = Key<CGFloat>("previewCornerRadius", default: 10, suite: .windowKit, iCloud: false)
    static let previewBorderThickness = Key<CGFloat>("previewBorderThickness", default: 4, suite: .windowKit, iCloud: false)
    static let previewUseWindowCornerRadius = Key<Bool>("previewUseWindowCornerRadius", default: true, suite: .windowKit, iCloud: false)
    static let previewBackgroundEnableBlur = Key<Bool>("previewBackgroundEnableBlur", default: true, suite: .windowKit, iCloud: false)
    static let previewBackgroundAccentOpacity = Key<CGFloat>("previewBackgroundAccentOpacity", default: 0.1, suite: .windowKit, iCloud: false)

    // Behavior
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false, suite: .windowKit, iCloud: false)
    static let startHidden = Key<Bool>("startHidden", default: false, suite: .windowKit, iCloud: false)
    static let hideMenuBarIcon = Key<Bool>("hideMenuBarIcon", default: false, suite: .windowKit, iCloud: false)
    static let animationConfiguration = Key<AnimationConfiguration>("animationConfiguration", default: .snappy, suite: .windowKit, iCloud: false)
    static let windowSnapping = Key<Bool>("windowSnapping", default: false, suite: .windowKit, iCloud: false)
    static let suppressMissionControlOnTopDrag = Key<Bool>("suppressMissionControlOnTopDrag", default: true, suite: .windowKit, iCloud: false)
    static let restoreWindowFrameOnDrag = Key<Bool>("restoreWindowFrameOnDrag", default: false, suite: .windowKit, iCloud: false)
    static let enablePadding = Key<Bool>("enablePadding", default: false, suite: .windowKit, iCloud: false)
    static let padding = Key<PaddingConfiguration>("padding", default: .zero, suite: .windowKit, iCloud: false)
    static let useScreenWithCursor = Key<Bool>("useScreenWithCursor", default: true, suite: .windowKit, iCloud: false)
    static let moveCursorWithWindow = Key<Bool>("moveCursorWithWindow", default: false, suite: .windowKit, iCloud: false)
    static let resizeWindowUnderCursor = Key<Bool>("resizeWindowUnderCursor", default: false, suite: .windowKit, iCloud: false)
    static let focusWindowOnResize = Key<Bool>("focusWindowOnResize", default: true, suite: .windowKit, iCloud: false)
    static let respectStageManager = Key<Bool>("respectStageManager", default: true, suite: .windowKit, iCloud: false)
    static let stageStripSize = Key<CGFloat>("stageStripSize", default: 150, suite: .windowKit, iCloud: false)
    static let animateStashedWindows = Key<Bool>("animateStashedWindows", default: true, suite: .windowKit, iCloud: false)
    static let stashedWindowVisiblePadding = Key<CGFloat>("stashedWindowVisiblePadding", default: 20, suite: .windowKit, iCloud: false)
    static let shiftFocusWhenStashed = Key<Bool>("shiftFocusWhenStashed", default: true, suite: .windowKit, iCloud: false)
    static let cycleModeRestartEnabled = Key<Bool>("cycleModeRestartEnabled", default: false, suite: .windowKit, iCloud: false)

    // Keybinds
    static let triggerKey = Key<Set<CGKeyCode>>("trigger", default: [.kVK_Function], suite: .windowKit, iCloud: false)
    static let sideDependentTriggerKey = Key<Bool>("sideDependentTriggerKey", default: true, suite: .windowKit, iCloud: false)
    static let triggerDelay = Key<Double>("triggerDelay", default: 0, suite: .windowKit, iCloud: false)
    static let doubleClickToTrigger = Key<Bool>("doubleClickToTrigger", default: false, suite: .windowKit, iCloud: false)
    static let middleClickTriggersLoop = Key<Bool>("middleClickTriggersLoop", default: false, suite: .windowKit, iCloud: false)
    static let enableTriggerDelayOnMiddleClick = Key<Bool>("enableTriggerDelayOnMiddleClick", default: false, suite: .windowKit, iCloud: false)
    static let cycleBackwardsOnShiftPressed = Key<Bool>("cycleBackwardsOnShiftPressed", default: true, suite: .windowKit, iCloud: false)
    static let keybinds = Key<[WindowAction]>("keybinds", default: WindowAction.defaultKeybinds, suite: .windowKit, iCloud: false)

    // Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: false, suite: .windowKit, iCloud: false)
    static let gestures = Key<[GestureBinding]>("gestures", default: GestureBinding.defaults, suite: .windowKit, iCloud: false)

    // Advanced
    static let useSystemWindowManagerWhenAvailable = Key<Bool>("useSystemWindowManagerWhenAvailable", default: false, suite: .windowKit, iCloud: false)
    static let animateWindowResizes = Key<Bool>("animateWindowResizes", default: false, suite: .windowKit, iCloud: false)
    static let disableCursorInteraction = Key<Bool>("disableCursorInteraction", default: false, suite: .windowKit, iCloud: false)
    static let ignoreFullscreen = Key<Bool>("ignoreFullscreen", default: false, suite: .windowKit, iCloud: false)
    static let hideOnNoSelectionForKeybinds = Key<Bool>("hideOnNoSelectionForKeybinds", default: false, suite: .windowKit, iCloud: false)
    static let hapticFeedback = Defaults.Key<Bool>("hapticFeedback", default: true, suite: .windowKit, iCloud: false)
    static let enableRadialMenuCustomization = Defaults.Key<Bool>("enableRadialMenuCustomization", default: false, suite: .windowKit, iCloud: false)
    static let sizeIncrement = Key<CGFloat>("sizeIncrement", default: 20, suite: .windowKit, iCloud: false)

    /// Excluded apps
    static let excludedApps = Key<[URL]>("excludedApps", default: [], suite: .windowKit, iCloud: false)

    // About
    #if RELEASE
        static let includeDevelopmentVersions = Key<Bool>("includeDevelopmentVersions", default: false, suite: .windowKit, iCloud: false)
    #else
        /// Development versions should check for development updates by default.
        static let includeDevelopmentVersions = Key<Bool>("includeDevelopmentVersions", default: true, suite: .windowKit, iCloud: false)
    #endif
    static let automaticallyUpdate = Key<Bool>("automaticallyUpdate", default: false, suite: .windowKit, iCloud: false)
}

// MARK: - Hidden Settings

extension Defaults.Keys {
    /// Hide the radial menu whenever a trackpad gesture has no selected action.
    /// Adjust with `defaults write com.MrKai77.Loop hideOnNoSelectionForGestures -bool false`
    /// Reset with `defaults delete com.MrKai77.Loop hideOnNoSelectionForGestures`
    static let hideOnNoSelectionForGestures = Key<Bool>("hideOnNoSelectionForGestures", default: true, suite: .windowKit, iCloud: false)

    /// Lock radial menu to the center of the screen
    /// Adjust with `defaults write com.MrKai77.Loop lockRadialMenuToCenter -bool true`
    /// Reset with `defaults delete com.MrKai77.Loop lockRadialMenuToCenter`
    static let lockRadialMenuToCenter = Key<Bool>("lockRadialMenuToCenter", default: false, suite: .windowKit, iCloud: false)

    /// Minimum screen size, defined in inches on the diagonal, for which padding will be applied on windows.
    /// Adjust with `defaults write com.MrKai77.Loop paddingMinimumScreenSize -float x`
    /// Reset with `defaults delete com.MrKai77.Loop paddingMinimumScreenSize`
    static let paddingMinimumScreenSize = Key<CGFloat>("paddingMinimumScreenSize", default: 0, suite: .windowKit, iCloud: false)

    /// Ignore the notch height when calculating top padding, so the effective
    /// distance from the screen top matches non-notch displays.
    /// Adjust with `defaults write com.MrKai77.Loop ignoreNotch -bool true`
    /// Reset with `defaults delete com.MrKai77.Loop ignoreNotch`
    static let ignoreNotch = Key<Bool>("ignoreNotch", default: false, suite: .windowKit, iCloud: false)

    /// Snap threshold for window snapping, defined in points.
    /// Adjust with `defaults write com.MrKai77.Loop snapThreshold -float x`
    /// Reset with `defaults delete com.MrKai77.Loop snapThreshold`
    static let snapThreshold = Key<CGFloat>("snapThreshold", default: 2, suite: .windowKit, iCloud: false)

    /// Whether to ignore low power mode for certain features, such as window animations.
    /// Adjust with `defaults write com.MrKai77.Loop ignoreLowPowerMode -bool x`
    /// Reset with `defaults delete com.MrKai77.Loop ignoreLowPowerMode`
    static let ignoreLowPowerMode = Key<Bool>("ignoreLowPowerMode", default: false, suite: .windowKit, iCloud: false)

    /// Adjust with `defaults write com.MrKai77.Loop previewStartingPosition [option]`
    /// Reset with `defaults delete com.MrKai77.Loop previewStartingPosition`
    ///
    /// Available options:
    /// - `screenCenter`: Center of the screen
    /// - `radialMenu`: Center of radial menu
    /// - `actionCenter`: Center of the selected action (e.g. for left half, it will grow from the center of that left half)
    static let previewStartingPosition = Key<PreviewStartingPosition>("previewStartingPosition", default: .actionCenter, suite: .windowKit, iCloud: false)

    /// Disable automatic updates with `defaults write com.MrKai77.Loop updatesEnabled -bool false`
    /// Reset with `defaults delete com.MrKai77.Loop updatesEnabled`
    static let updatesEnabled = Key<Bool>("updatesEnabled", default: true, suite: .windowKit, iCloud: false)

    /// Trigger key timeout, defined in seconds. Automatically closes Loop if no action is taken within the specified time.
    /// When set to 0 (default: disabled), the feature is disabled and Loop stays open until manually closed.
    /// Adjust with `defaults write com.MrKai77.Loop triggerKeyTimeout -float x`
    /// Reset with `defaults delete com.MrKai77.Loop triggerKeyTimeout`
    static let triggerKeyTimeout = Key<Double>("triggerKeyTimeout", default: 0, suite: .windowKit, iCloud: false)

    /// Height of the titlebar activation zone for gestures, defined in points.
    /// Gestures with the `.titlebar` activation zone will only trigger when the cursor is within this distance from the top of a window.
    /// Adjust with `defaults write com.MrKai77.Loop gestureTitlebarHeight -float x`
    /// Reset with `defaults delete com.MrKai77.Loop gestureTitlebarHeight`
    static let gestureTitlebarHeight = Key<CGFloat>("gestureTitlebarHeight", default: 50, suite: .windowKit, iCloud: false)

    /// Whether to sync all Loop settings to iCloud.
    /// Adjust with `defaults write com.MrKai77.Loop enableiCloudSync -bool false`
    /// Reset with `defaults delete com.MrKai77.Loop enableiCloudSync`
    static let enableiCloudSync = Key<Bool>("enableiCloudSync", default: true, suite: .windowKit, iCloud: false)
}

// MARK: - Non-user-intended Settings

extension Defaults.Keys {
    // Migrator

    static let lastMigratorURL = Key<URL?>("lastMigratorURL", default: nil, suite: .windowKit, iCloud: false)

    // StashManager

    static let stashManagerStashedWindows = Key<[CGWindowID: WindowAction]>("stashManagerStashed", default: [:], suite: .windowKit, iCloud: false)

    // AccentColorController

    static let lastUsedAccentColor1 = Key<Color>("lastUsedAccentColor1", default: .black, suite: .windowKit, iCloud: false)
    static let lastUsedAccentColor2 = Key<Color>("lastUsedAccentColor2", default: .black, suite: .windowKit, iCloud: false)

    // Settings

    static let showSettingsInspector = Key<Bool>("showSettingsInspector", default: true, suite: .windowKit, iCloud: false)
}

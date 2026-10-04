# Loop

- Repo: https://github.com/MrKai77/Loop
- Commit: 0ac6d834fb2cb542e62748021a88ee0f6a728fd7 (2026-09-29)
- License: GPL-3.0 (see LICENSE in this folder)
- Used for: window management, vendored as WindowKit (stage 3). Changes offered back upstream must follow Loop's AI_POLICY.md.

## Files taken

Copied as plain files (no git history) into `Packages/WindowKit`, keeping Loop's folder names:

- `Loop/<path>` → `Packages/WindowKit/Sources/WindowKit/Loop/<path>` for the 135 source files listed below.
- `Loop/Assets.xcassets/Contents.json` and `Loop/Assets.xcassets/loop.symbolset/` (the `loop` symbol, used by `Image(.loop)` in four files) → `Packages/WindowKit/Sources/WindowKit/Resources/Assets.xcassets/`.
- `Loop/Localizable.xcstrings` → `Packages/WindowKit/Sources/WindowKit/Resources/Localizable.xcstrings` (English and Loop's existing translations).
- `LoopTests/<file>` → `Packages/WindowKit/Tests/WindowKitTests/Loop/<file>`, all six: `CycleActionCoordinatorTests.swift`, `CycleProgressStoreTests.swift`, `KeybindResolverTests.swift`, `MultitouchGestureActivationTests.swift`, `OverlappingKeybindCycleTests.swift`, `SystemGestureFilterTests.swift`. No test was dropped.

Source files (paths relative to `Loop/` upstream and to `Sources/WindowKit/Loop/` here):

- `Accent Color/AccentColorController.swift`
- `Accent Color/AccentColorOption.swift`
- `Accent Color/WallpaperImageFetcher.swift`
- `Accent Color/WallpaperProcessor.swift`
- `Core/LoopManager.swift`
- `Core/Multitouch/Debug/GestureDebugOverlayController.swift`
- `Core/Multitouch/Debug/GestureDebugOverlayModel.swift`
- `Core/Multitouch/Debug/GestureDebugOverlayView.swift`
- `Core/Multitouch/MultitouchGestureBlocker.swift`
- `Core/Multitouch/MultitouchGestureSession.swift`
- `Core/Multitouch/MultitouchRecognizerRegistry.swift`
- `Core/Multitouch/MultitouchTargetResolver.swift`
- `Core/Multitouch/MultitouchTrigger+Magnify.swift`
- `Core/Multitouch/MultitouchTrigger+Swipe.swift`
- `Core/Multitouch/MultitouchTrigger.swift`
- `Core/Multitouch/RadialGestureGeometry.swift`
- `Core/Multitouch/SystemGestureFilter.swift`
- `Core/Observers/Helpers/DoubleClickTimer.swift`
- `Core/Observers/Helpers/KeybindResolver.swift`
- `Core/Observers/Helpers/TriggerDelayTimer.swift`
- `Core/Observers/Helpers/TriggerKeyTimeoutTimer.swift`
- `Core/Observers/KeybindTrigger.swift`
- `Core/Observers/MiddleClickTrigger.swift`
- `Core/Observers/MouseInteractionObserver.swift`
- `Core/WindowDragManager.swift`
- `Extensions/AXUIElement+Extensions.swift`
- `Extensions/Angle+Extensions.swift`
- `Extensions/Binding+Extensions.swift`
- `Extensions/Bundle+Extensions.swift`
- `Extensions/CGEvent+Extensions.swift`
- `Extensions/CGEventField+Extensions.swift`
- `Extensions/CGEventFlags+Extensions.swift`
- `Extensions/CGEventType+Extensions.swift`
- `Extensions/CGGeometry+Extensions.swift`
- `Extensions/CGKeyCode+Extensions.swift`
- `Extensions/Defaults+Extensions.swift`
- `Extensions/FileManager+Extensions.swift`
- `Extensions/Int64+Extensions.swift`
- `Extensions/NSColor+Extensions.swift`
- `Extensions/NSScreen+Extensions.swift`
- `Extensions/OperatingSystemVersion+Extensions.swift`
- `Extensions/ProcessInfo+Extensions.swift`
- `Extensions/RectangleCornerRadii+Extensions.swift`
- `Extensions/UNNotification+Extensions.swift`
- `Private APIs/PrivateApis.swift`
- `Private APIs/SLSWindowTags.swift`
- `Private APIs/SkyLightBridgedSPI.swift`
- `Private APIs/SkyLightSymbolLoader.swift`
- `Private APIs/SkyLightToolBelt.swift`
- `Settings Window/Loop/AdvancedConfiguration.swift`
- `Settings Window/Loop/ExcludedAppsConfiguration.swift`
- `Settings Window/Settings/Behavior/BehaviorConfiguration.swift`
- `Settings Window/Settings/Behavior/Padding Configuration/PaddingConfigurationView.swift`
- `Settings Window/Settings/Behavior/Padding Configuration/PaddingPreview.swift`
- `Settings Window/Settings/Gestures/GestureConfigurationView.swift`
- `Settings Window/Settings/Gestures/GestureItemView.swift`
- `Settings Window/Settings/Gestures/GesturesConfigurationView.swift`
- `Settings Window/Settings/Keybinds/DirectionPickerView.swift`
- `Settings Window/Settings/Keybinds/Keybind Recorder/Keycorder.swift`
- `Settings Window/Settings/Keybinds/Keybind Recorder/TriggerKeycorder.swift`
- `Settings Window/Settings/Keybinds/KeybindItemView.swift`
- `Settings Window/Settings/Keybinds/KeybindsConfigurationView.swift`
- `Settings Window/Settings/Keybinds/Modal Views/ActionPreview.swift`
- `Settings Window/Settings/Keybinds/Modal Views/CustomActionConfigurationView.swift`
- `Settings Window/Settings/Keybinds/Modal Views/CycleActionConfigurationView.swift`
- `Settings Window/Settings/Keybinds/Modal Views/ScreenView.swift`
- `Settings Window/Settings/Keybinds/Modal Views/StashActionConfigurationView.swift`
- `Settings Window/SettingsContentView.swift`
- `Settings Window/SettingsTab.swift`
- `Settings Window/SettingsWindowManager.swift`
- `Settings Window/Theming/AccentColorConfiguration.swift`
- `Settings Window/Theming/PreviewConfiguration.swift`
- `Settings Window/Theming/Radial Menu/RadialMenuActionItemView.swift`
- `Settings Window/Theming/Radial Menu/RadialMenuActionPickerView.swift`
- `Settings Window/Theming/Radial Menu/RadialMenuActionsGuide.swift`
- `Settings Window/Theming/Radial Menu/RadialMenuConfigurationView.swift`
- `Stashing/StashDirection.swift`
- `Stashing/StashManager.swift`
- `Stashing/StashedWindowInfo.swift`
- `Stashing/StashedWindowStore.swift`
- `Utilities/AccessibilityManager.swift`
- `Utilities/AnimationConfiguration.swift`
- `Utilities/DirectionalNavigationUtility.swift`
- `Utilities/Event Monitoring/ActiveEventMonitor.swift`
- `Utilities/Event Monitoring/BaseEventTapMonitor.swift`
- `Utilities/Event Monitoring/EventMonitorProtocol.swift`
- `Utilities/Event Monitoring/EventTapThread.swift`
- `Utilities/Event Monitoring/LocalEventMonitor.swift`
- `Utilities/Event Monitoring/PassiveEventMonitor.swift`
- `Utilities/MissionControl.swift`
- `Utilities/PickerList.swift`
- `Utilities/PickerListEventMonitorManager.swift`
- `Utilities/ScreenUtility.swift`
- `Utilities/ShakeEffect.swift`
- `Utilities/VisualEffectView.swift`
- `Window Action Indicators/ActivePanel.swift`
- `Window Action Indicators/Preview Window/PreviewController.swift`
- `Window Action Indicators/Preview Window/PreviewStartingPosition.swift`
- `Window Action Indicators/Preview Window/PreviewView.swift`
- `Window Action Indicators/Preview Window/PreviewViewModel.swift`
- `Window Action Indicators/Radial Menu/DirectionSelectorCircleSegment.swift`
- `Window Action Indicators/Radial Menu/DirectionSelectorSquareSegment.swift`
- `Window Action Indicators/Radial Menu/RadialLayout.swift`
- `Window Action Indicators/Radial Menu/RadialMenuController.swift`
- `Window Action Indicators/Radial Menu/RadialMenuView.swift`
- `Window Action Indicators/Radial Menu/RadialMenuViewModel.swift`
- `Window Action Indicators/WindowActionIndicator.swift`
- `Window Action Indicators/WindowActionIndicatorService.swift`
- `Window Management/SystemWindowManager.swift`
- `Window Management/Window Action/Custom Window Sizes/CustomWindowActionAnchor.swift`
- `Window Management/Window Action/Custom Window Sizes/CustomWindowActionPositionMode.swift`
- `Window Management/Window Action/Custom Window Sizes/CustomWindowActionSizeMode.swift`
- `Window Management/Window Action/Custom Window Sizes/CustomWindowActionUnit.swift`
- `Window Management/Window Action/CycleActionCoordinator.swift`
- `Window Management/Window Action/CycleProgressStore.swift`
- `Window Management/Window Action/GestureBinding.swift`
- `Window Management/Window Action/IconView.swift`
- `Window Management/Window Action/RadialMenuAction.swift`
- `Window Management/Window Action/WindowAction+Defaults.swift`
- `Window Management/Window Action/WindowAction+Image.swift`
- `Window Management/Window Action/WindowAction.swift`
- `Window Management/Window Action/WindowActionCache.swift`
- `Window Management/Window Action/WindowDirection+LocalizedString.swift`
- `Window Management/Window Action/WindowDirection+Snapping.swift`
- `Window Management/Window Action/WindowDirection.swift`
- `Window Management/Window Manipulation/PaddingConfiguration.swift`
- `Window Management/Window Manipulation/ResizeContext.swift`
- `Window Management/Window Manipulation/WindowActionEngine.swift`
- `Window Management/Window Manipulation/WindowEngine.swift`
- `Window Management/Window Manipulation/WindowFrameResolver.swift`
- `Window Management/Window Manipulation/WindowRecords.swift`
- `Window Management/Window Manipulation/WindowTransformAnimation.swift`
- `Window Management/Window/Window.swift`
- `Window Management/Window/WindowUtility+FocusNavigation.swift`
- `Window Management/Window/WindowUtility.swift`

### Left out

- `Loop/App/` (all of it: `AppDelegate.swift`, `AppDelegate+UNNotifications.swift`, `DataPatcher.swift`, `LaunchAtLoginManager.swift`, `LoopApp.swift`, which holds Loop's own status item). Wiring reference only.
- `Loop/Updater/`, `LoopUpdaterHelper/`, `LoopDockTile/`, `Loop/Migration/`, `Loop/Icon/`.
- `Loop/Core/URLCommandHandler.swift`.
- `Loop/Settings Window/Loop/AboutConfiguration.swift` (the About page) and `Loop/Settings Window/Theming/IconConfiguration.swift` (the Icon page, built on `Icon/`).
- `Loop/Extensions/View+Extensions.swift`: its only content is a macOS 13 backport of `onChange(of:initial:action:)`, which is ambiguous with SwiftUI's own `onChange(of:initial:_:)` once the target is macOS 14 (two call sites failed to compile). The callers now get SwiftUI's version, which behaves the same.
- `Shared/PrivilegedInstallerProtocol.swift` (updater helper) and `Shared/LoopSupportPaths.swift` (only the updater refers to it).
- Resources: `Loop/Assets.xcassets/App Icons/`, `Loop/Assets.xcassets/menubarIcon.imageset`, `Loop/Assets.xcassets/Credits/` (only the About page uses it), `Loop/Resources/AppIcon-*.icon`, `Loop/*.lproj/InfoPlist.strings`, `Info.plist`, `InternetAccessPolicy.plist`, `Loop.entitlements`, `Config.xcconfig`.
- Repo files: `Loop.xcodeproj`, `assets/`, README, contributing and policy files.

### Build settings

- Swift 5 language mode (Loop builds with `SWIFT_VERSION = 5.0`), plus the upcoming features that Loop's `SWIFT_APPROACHABLE_CONCURRENCY = YES` turns on: `DisableOutwardActorInference`, `GlobalActorIsolatedTypesUsability`, `InferIsolatedConformances`, `InferSendableFromCaptures`, `NonisolatedNonsendingByDefault`. The tests also get `MemberImportVisibility`, as in Loop's test target.
- Deployment target macOS 14 (Loop: 13). This brings 31 deprecation warnings (29 `onChange(of:perform:)`, one `CGWindowListCreateImage`, one `activateIgnoringOtherApps`), left as they are.
- SkyLight is loaded at run time (`SkyLightSymbolLoader`), so nothing links the private framework. `GetProcessForPID` and `_AXUIElementGetWindow` come from ApplicationServices.

### Dependencies

Loop tracks these on `main` with no `Package.resolved`, so WindowKit pins them in `Packages/WindowKit/Package.swift`, and `Packages/WindowKit/Package.resolved` is committed.

| Package | Pin | Commit date | Why |
|---|---|---|---|
| Defaults (sindresorhus/Defaults) | `exact: "9.0.9"` | | Matches the app's `project.yml`. Loop asks for `upToNextMajor` from 9.0.0. |
| Luminare (mrkai77/Luminare) | `revision: 99c14e36cd536c8252ea147c36e270675fe9c187` | 2026-09-28 | `main` nearest 2026-09-29; no later commit exists. Compiles. |
| Subsurface (mrkai77/Subsurface) | `revision: 660fe2bd7fbefe8f60b587905748b8e1ea413e2f` | 2026-09-29 20:40 -0600 | The last `main` commit on 2026-09-29. Compiles and Loop's tests pass. It is about ten hours after the Loop snapshot (10:05 -0600); the commit current at the snapshot was `5e0692279b969de3ac399100c5904ca53f3a51f5` (2026-09-10). Newer: `88eb16b` (2026-09-30), not tried. |
| Scribe (SenpaiHunters/Scribe) | `branch: "main"`, resolved to `658180864653457ce201917200bac67ee3eeac87` | 2026-01-23 | Newest `main` commit (no tags). It cannot be pinned with `revision:`: Subsurface asks for Scribe `branch: "main"`, and SwiftPM refuses two different revision-based requirements for one package (`scribe is required using two different revision-based requirements`). `Package.resolved` holds the commit. |

Transitive, as resolved: swift-syntax 602.0.0 (for Scribe's macros), swiftui-introspect 1.4.0 and swiftui-variadic-views 1.0.0 (for Luminare).

## Modifications

Each changed file starts with `// Adapted from Loop@0ac6d83: <original path>`. The first list is compile fixes for the left-out files or the package build. The second list (isolation and gating) changes behaviour, as each entry says; Mooring-written code sits outside `Loop/` (`WindowKit.swift`, `WindowKit+Actions.swift`, `Capabilities.swift`, `ScreenSwitchFrames.swift`, `WindowChord.swift`, `WindowSettingsPage.swift`).

- `Loop/Core/LoopManager.swift`: removed the `updater` property (`Updater.shared`), the `IconManager.checkIfUnlockedNewIcon()` call, and the `Task` at the end of `closeLoop` that showed the update window. `Defaults[.timesLooped] += 1` stays.
- `Loop/Extensions/Defaults+Extensions.swift`: removed the `patchesApplied` key (type `DataPatcher.Patches`). The other keys, including `lastMigratorURL`, are unchanged.
- `Loop/Settings Window/Loop/AdvancedConfiguration.swift`: removed the Keybinds section's Import and Export buttons, their `importPrompt()` / `exportPrompt()` methods (they called `Migrator`) and their two success-indicator properties. Reset stays.
- `Loop/Settings Window/SettingsTab.swift`: removed the `icon` and `about` cases and their colour, title, image and view branches; dropped them from `themingTabs` and `loopTabs`; `showIndicator` (only `about` used it, through `Updater`) is now always `false`; `Image(.loop)` → `Image("loop", bundle: .module)`.
- `Loop/Settings Window/SettingsWindowManager.swift`: the default `currentTab` is `.accentColor`, since `.icon` is gone.
- `Loop/Settings Window/Settings/Gestures/GestureConfigurationView.swift`, `Loop/Settings Window/Settings/Gestures/GestureItemView.swift`, `Loop/Window Management/Window Action/GestureBinding.swift`: `Image(.loop)` → `Image("loop", bundle: .module)`. SwiftPM generates no asset symbols, so `ImageResource.loop` does not exist in the package.
- `LoopTests/*.swift` (all six): `@testable import Loop` → `@testable import WindowKit`.
- `Loop/Extensions/View+Extensions.swift`: not taken (see Left out).

### Isolation and gating

- `Loop/Extensions/Defaults+Extensions.swift`: every key (76) now passes `suite: .windowKit, iCloud: false`, where `UserDefaults.windowKit` is `UserDefaults(suiteName: "dev.mooring.windows")!` (or the scratch suite `dev.mooring.windows.tests` when Swift Testing or XCTest is loaded), so Loop's settings never land in Mooring's `UserDefaults.standard`. Removed `DefaultsiCloudSyncRegistrar` (which added most keys to `Defaults.iCloud`); the `enableiCloudSync` key stays but nothing reads it.
- `Loop/Private APIs/PrivateApis.swift`: the two `@_silgen_name` bindings (`GetProcessForPID`, `_AXUIElementGetWindow`) are now functions with the same signatures that call a pointer resolved through `Capabilities.liveSymbol` (`dlsym`). A missing symbol returns `procNotFound` / `.apiDisabled` instead of stopping the app at launch.
- `Loop/Private APIs/SkyLightSymbolLoader.swift`: `loadSymbol` resolves through `Capabilities.liveSymbol` (SkyLight first, then the process); the private `dlopen` handle and framework path are gone.
- `Loop/Private APIs/SkyLightBridgedSPI.swift`: `objcMessageSend` is a computed property, resolved through `Capabilities.liveSymbol` and `nil` while `Capabilities.active.skyLightMoves` is false, so every space operation fails closed.
- `Loop/Private APIs/SkyLightToolBelt.swift`: `makeFrontProcess` and `makeKeyWindow` return `false` while `Capabilities.active.windowFocus` is false (callers already fall back to `activate`). `bestManagedDisplayID`, `windowIDAtPosition`, `getWindowLevel` and `getCornerRadii` return `nil` while `windowDetails` is false, and `setBackgroundBlur`, `captureWindowList` and `refreshIconAppearanceCache` do nothing (or return `[]`) while `windowEffects` is false; every caller already has a fallback for those results.
- `Loop/Extensions/AXUIElement+Extensions.swift`: `getWindowID()` throws `AXError.apiDisabled` while `Capabilities.active.windowIDLookup` is false, so no `Window` can be made and every action is a no-op.
- `Loop/Utilities/ScreenUtility.swift`: next/previous screen ordering moved into generic `next(from:in:frame:canRestartCycle:)` / `previous(...)`, which take the screens and a frame accessor; `nextScreen` / `previousScreen` call them with `NSScreen.screens` and `\.frame`. The private `Array.next/previous` helpers now need `Equatable` instead of `Hashable`. Behaviour unchanged; it is the frame-maths test seam.
- `Loop/Core/LoopManager.swift`: `shared` goes through `WindowKit.track(_:)`; `indicatorService` is internal (was `private`) so tests can show the radial menu; `shutdown()` calls `indicatorService.closeAllImmediately()` instead of the animated `closeAll()`. `closeLoop` keeps Loop's animated `closeAll()`.
- `Loop/Core/WindowDragManager.swift`: `shared` goes through `WindowKit.track(_:)`; `shutdown()` closes its preview with `closeImmediately()`.
- `Loop/Window Action Indicators/Radial Menu/RadialMenuController.swift`, `Loop/Window Action Indicators/Preview Window/PreviewController.swift`: added `closeImmediately()` (cancel any pending close, mark the view model hidden, order out and drop the panel, no fade).
- `Loop/Window Action Indicators/WindowActionIndicatorService.swift`: added `closeAllImmediately()`.
- `Loop/Utilities/AccessibilityManager.swift`: `shared` goes through `WindowKit.track(_:)`; added `activeStreamCount` (tests count observers with it); removed `requestAccess()` and the two `tccutil reset` helpers (Accessibility and Input Monitoring for the app's bundle id). Mooring owns the Accessibility request.
- `Loop/Settings Window/Loop/AdvancedConfiguration.swift`: removed the Permissions section (its "Request…" button called `requestAccess()`), and the model's Accessibility tracking; the low-power tracking now hangs off the Keybinds section.
- `Loop/Settings Window/Loop/ExcludedAppsConfiguration.swift`: the app chooser falls back to `NSApp.keyWindow` when Loop's own settings window doesn't exist (the pages are hosted in Mooring's Settings).
- `Loop/Settings Window/Theming/PreviewConfiguration.swift`: the "Prioritize selected window’s corner radius" toggle shows only while `Capabilities.active.windowDetails` is true, and the slider's label follows.
- `Loop/Utilities/PickerList.swift`: `PickerSection.windowDirections` (the Keybinds and Radial Menu action pickers) no longer lists the Focus and Stash sections; stash and focus switching stay hidden in 3a.
- `Loop/Settings Window/Settings/Behavior/BehaviorConfiguration.swift`: the Stash section is no longer in the page (the view code stays).
- `Loop/Window Management/Window Manipulation/WindowActionEngine.swift`: `shared` goes through `WindowKit.track(_:)`; `performApply` returns `.noOp` for stash, unstash and the focus actions, and `resolveFocusTarget` returns `nil` for them (so `LoopManager` focuses nothing), so a leftover binding does nothing in 3a.
- `shared` routed through `WindowKit.track(_:)` (counted by `WindowKit.instantiatedSingletons`), no other change: `Loop/Settings Window/SettingsWindowManager.swift`, `Loop/Accent Color/AccentColorController.swift`, `Loop/Utilities/PickerListEventMonitorManager.swift`, `Loop/Utilities/Event Monitoring/EventTapThread.swift`, `Loop/Stashing/StashManager.swift`, `Loop/Window Management/Window Manipulation/WindowRecords.swift`.

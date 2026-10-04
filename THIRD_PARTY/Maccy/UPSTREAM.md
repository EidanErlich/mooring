# Maccy

- Repo: https://github.com/p0deje/Maccy
- Commit: c376789c5d377b7c520b6f6e91f3f3a1aa28640b (2026-09-04)
- License: MIT (see LICENSE in this folder)
- Used for: the dropdown's floating panel (stage 1b, since removed) and clipboard history, vendored as ClipKit (stage 4), with its popup panel

## Files taken

| Upstream file | Mooring file |
| --- | --- |
| `Maccy/FloatingPanel.swift` | `App/UI/FloatingPanel.swift` (stage 1b; deleted when the dropdown became a real menu) |
| `Maccy/FloatingPanel.swift` | `App/UI/ClipboardPanel.swift` and `Packages/ClipKit/Sources/ClipKit/ClipKitPopup.swift` (stage 4 task 4) |

### Stage 4: ClipKit

Copied as plain files (no git history) into `Packages/ClipKit`, keeping Maccy's folder names:

- `Maccy/<path>` → `Packages/ClipKit/Sources/ClipKit/Maccy/<path>` for the 87 source files listed below.
- `Maccy/en.lproj/Localizable.strings` → `Packages/ClipKit/Sources/ClipKit/Resources/en.lproj/Localizable.strings`.
- `Maccy/Views/en.lproj/PreviewItemView.strings` → `Packages/ClipKit/Sources/ClipKit/Resources/en.lproj/PreviewItemView.strings`.
- `Maccy/Sounds/Knock.caf`, `Maccy/Sounds/Write.caf` → `Packages/ClipKit/Sources/ClipKit/Resources/Sounds/`.
- `Maccy/Settings/en.lproj/AppearanceSettings.strings`, `GeneralSettings.strings`, `StorageSettings.strings` → `Packages/ClipKit/Sources/ClipKit/Resources/en.lproj/` (stage 4 task 2): the kept `PopupPosition`, `PinsPosition`, `SearchVisibility`, `HighlightMatch`, `Search.Mode` and `Sorter.By` descriptions look up these tables.
- `MaccyTests/<file>` → `Packages/ClipKit/Tests/ClipKitTests/Maccy/<file>`, all ten: `ClipboardTests.swift`, `CollectionSurroundingTests.swift`, `ColorImageTests.swift`, `HistoryDecoratorTests.swift`, `HistoryItemTests.swift`, `HistoryTests.swift`, `SearchTests.swift`, `ShortenedTests.swift`, `SorterTests.swift`, `UnsafeForTitleLayoutTests.swift` (91 tests). No test was dropped.
- `MaccyTests/Fixtures/guy.jpeg` → `Packages/ClipKit/Tests/ClipKitTests/Maccy/Fixtures/guy.jpeg`.

Source files (paths relative to `Maccy/` upstream and to `Sources/ClipKit/Maccy/` here):

- `Accessibility.swift`
- `ApplicationImage.swift`
- `ApplicationImageCache.swift`
- `Clipboard.swift`
- `ColorImage.swift`
- `Extensions/Collection+Surrounding.swift`
- `Extensions/Color+Random.swift`
- `Extensions/Defaults.Keys+Names.swift`
- `Extensions/Dictionary+RemoveItem.swift`
- `Extensions/KeyEquivalent+Keys.swift`
- `Extensions/KeyboardShortcuts.Name+Shortcuts.swift`
- `Extensions/ModifierFlags+Current.swift`
- `Extensions/ModifierFlags+Description.swift`
- `Extensions/NSApplication+Windows.swift`
- `Extensions/NSImage+Names.swift`
- `Extensions/NSImage+Resized.swift`
- `Extensions/NSPasteboard.PasteboardType+Types.swift`
- `Extensions/NSPoint+DefaultsSerializable.swift`
- `Extensions/NSRect+Centered.swift`
- `Extensions/NSRunningApplication+WindowFrame.swift`
- `Extensions/NSScreen+ForPopup.swift`
- `Extensions/NSSize+DefaultsSerializable.swift`
- `Extensions/NSSound+Named.swift`
- `Extensions/NSWorkspace+ApplicationName.swift`
- `Extensions/Sauce+KeyboardShortcuts.swift`
- `Extensions/String+Identifiable.swift`
- `Extensions/String+Shortened.swift`
- `Extensions/String+UnsafeForTitleLayout.swift`
- `Extensions/View+ButtonAction.swift`
- `Extensions/View+Invisible.swift`
- `HighlightMatch.swift`
- `HistoryItemAction.swift`
- `ItemsProtocol.swift`
- `KeyChord.swift`
- `KeyShortcut.swift`
- `KeyboardLayout.swift`
- `Models/HistoryItem.swift`
- `Models/HistoryItemContent.swift`
- `Notifier.swift`
- `Observables/AppState.swift`
- `Observables/Footer.swift`
- `Observables/FooterItem.swift`
- `Observables/History.swift`
- `Observables/HistoryItemDecorator.swift`
- `Observables/ModifierFlags.swift`
- `Observables/NavigationManager.swift`
- `Observables/Popup.swift`
- `Observables/SlideoutController.swift`
- `PasteStack.swift`
- `PinsPosition.swift`
- `PopupPosition.swift`
- `Search.swift`
- `SearchVisibility.swift`
- `Selection.swift`
- `Sorter.swift`
- `Storage.swift`
- `Throttler.swift`
- `Views/AppImageView.swift`
- `Views/AsyncView.swift`
- `Views/ConfirmationView.swift`
- `Views/ContentView.swift`
- `Views/FooterItemView.swift`
- `Views/FooterView.swift`
- `Views/HeaderView.swift`
- `Views/HeightReaderModifier.swift`
- `Views/HistoryItemView.swift`
- `Views/HistoryListView.swift`
- `Views/HoverSelectionModifier.swift`
- `Views/KeyHandlingView.swift`
- `Views/KeyboardShortcutView.swift`
- `Views/ListHeaderView.swift`
- `Views/ListItemTitleView.swift`
- `Views/ListItemView.swift`
- `Views/MouseMovedViewModifer.swift`
- `Views/MultipleSelectionListView.swift`
- `Views/PasteStackItemView.swift`
- `Views/PasteStackPreviewView.swift`
- `Views/PasteStackView.swift`
- `Views/PinsView.swift`
- `Views/PreviewItemView.swift`
- `Views/SearchFieldView.swift`
- `Views/SlideoutContentView.swift`
- `Views/SlideoutView.swift`
- `Views/ToolbarView.swift`
- `Views/VisualEffectView.swift`
- `Views/WrappingTextView.swift`
- `VoiceOver.swift`

### Left out

- `Intents/` (all six: `AppIntentError.swift`, `Clear.swift`, `Delete.swift`, `Get.swift`, `HistoryItemAppEntity.swift`, `Select.swift`), `SoftwareUpdater.swift`, `AppStoreReview.swift`, `About.swift`, `MenuIcon.swift`, `Settings/` (all panes, and their strings apart from the three English tables above; rebuilt later as Mooring's Clipboard pages), `AppDelegate.swift` and `MaccyApp.swift` (wiring reference only).
- `FloatingPanel.swift`: not needed to compile; the views reach the panel through `PopupPanel` (see Modifications). Task 4 adapts it into `App/UI/ClipboardPanel.swift` (see below).
- `GlobalHotKey.swift`: not in Maccy's own build target and referenced by nothing; it calls `KeyboardShortcuts.Shortcut.toKeyEquivalent()` / `toEventModifiers()`, which no KeyboardShortcuts release has (2.0.2 to 2.4.0 checked), so it does not compile.
- `Extensions/Settings.PaneIdentifier+Panes.swift`: only Maccy's Settings window uses it, and it needs the Settings package.
- `Storage.xcdatamodeld` and `History.xcdatamodeld`: neither is in Maccy's build target nor referenced by code. The store is SwiftData (`@Model` classes); there is no SwiftData migration plan. `History.xcdatamodeld` is empty.
- Resources: `Assets.xcassets` (the app icon, `StatusBarMenuImage`, and the `clipboard.fill`, `paperclip` and `scissors` menu-bar icons, which only `MenuIcon` uses), `AppIcon.icon/`, `Info.plist`, `Maccy.entitlements`.
- Localisation: English only. Left out: the other 42 `Localizable.strings` (`ar`, `be`, `bn`, `bs`, `ca`, `ckb`, `cs`, `de`, `el`, `eo`, `es`, `fa`, `fi`, `fr`, `he`, `hi`, `hr`, `hu`, `id`, `it`, `ja`, `km`, `ko`, `lt`, `lv`, `nb`, `nl`, `pl`, `pt`, `pt-BR`, `ro`, `ru`, `sl`, `sv`, `ta`, `th`, `tr`, `uk`, `uz`, `vi`, `zh-Hans`, `zh-Hant`) and the same 42 locales of `Views/*.lproj/PreviewItemView.strings`.
- `MaccyTests/Info.plist`, `MaccyUITests/`, `Maccy.xctestplan`, `Maccy.xcodeproj`, `Designs/`, `docs/`, `appcast.xml`, README.

### Build settings

- Swift 5 language mode (Maccy builds with `SWIFT_VERSION = 5.0`, no upcoming features). Deployment target macOS 14, as Maccy's. `defaultLocalization: "en"`.
- Resources: `.process("Resources")` for the target (sounds and English strings, flattened into the bundle); `.process("Maccy/Fixtures")` for the tests.
- Warnings, left as they are: `AppState` is a non-final `Sendable` class with mutable state (2), and two `@Sendable` closure captures of `self` in `HistoryItemDecorator`.

### Dependencies

Pinned exactly in `Packages/ClipKit/Package.swift`; `Packages/ClipKit/Package.resolved` is committed.

| Package | Pin | Maccy's requirement | Note |
|---|---|---|---|
| Defaults (sindresorhus/Defaults) | `exact: "9.0.9"` | up to next minor from 8.2.0 | Matches the app and WindowKit. Every Maccy call compiled against 9.0.9 unchanged; no adaptation was needed. |
| KeyboardShortcuts (sindresorhus/KeyboardShortcuts) | `exact: "2.0.2"` | up to next minor from 2.0.2 | Maccy's minimum and its resolved version; builds with Swift 6 tools on macOS 14. |
| Sauce (Clipy/Sauce) | `exact: "2.4.1"` | up to next minor from 2.4.1 | |
| SwiftHEXColors (thii/SwiftHEXColors) | `exact: "1.4.1"` | up to next minor from 1.4.1 | |
| Fuse (krisk/fuse-swift) | `exact: "1.4.0"` | up to next major from 1.4.0 | |
| swift-log (apple/swift-log) | `exact: "1.6.4"` | up to next major from 1.6.4 | |

Not taken: Sparkle, Settings, LaunchAtLogin-Modern (their only users, `SoftwareUpdater`, `Settings/`, `AppState.openPreferences` and `AppDelegate`, are left out or trimmed).

Transitive, as resolved: swift-syntax 602.0.0 (for Defaults' macros; Defaults allows 600..<606). ClipKit's own `Package.resolved` is held at 602.0.0 to match the app's graph, where Scribe already fixes it.

## Modifications

Each changed file starts with `// Adapted from Maccy@c376789: <original path>`. These are compile fixes for the left-out files and the package build; behaviour is unchanged except where an entry says so. Mooring-written code sits outside `Maccy/` (`TestHost.swift`, `PopupPanel.swift`).

- `Maccy/Observables/AppState.swift`: removed `import Settings`, the `about` and `settingsWindowController` properties and `openAbout()`; `openPreferences()` is now empty (Maccy's Settings window isn't taken). `var appDelegate: AppDelegate?` → `var panel: (any PopupPanel)?`.
- `Maccy/Observables/Footer.swift`: removed the "about" footer item (it called `openAbout()`). The "preferences" item stays; since task 4 it opens Mooring's Settings (see `AppState.swift` under task 4).
- `Maccy/Observables/Popup.swift`, `Maccy/Observables/SlideoutController.swift`, `Maccy/Views/SlideoutView.swift`, `Maccy/Views/ToolbarView.swift`: `AppState.shared.appDelegate?.panel` / `appState.appDelegate?.panel` → `AppState.shared.panel` / `appState.panel` (seven call sites).
- `Maccy/Observables/History.swift`: removed the unused `import Settings`.
- `Maccy/Extensions/Defaults.Keys+Names.swift`: `AppDelegate.isTesting` → `TestHost.isActive`; removed the `menuIcon` key (its type, `MenuIcon`, isn't taken).
- `Maccy/Storage.swift`: `AppDelegate.isTesting` → `TestHost.isActive`, so the store is in memory under any test host. Maccy keyed this on the `enable-testing` launch argument that its test plan passes. (Reworked in task 2, below.)
- `Maccy/Extensions/NSSound+Named.swift`: `Bundle.main` → `Bundle.module` for `Knock.caf` and `Write.caf`.
- `Maccy/Notifier.swift`: `notify(body:sound:)` returns early unless the main bundle is an `.app`. `UNUserNotificationCenter.current()` raises an exception in `swift test`'s bare `xctest` tool, which crashed the test run. (Replaced in task 2 by a no-op, below.)
- `MaccyTests/*.swift` (all ten): `@testable import Maccy` → `@testable import ClipKit`.
- `MaccyTests/HistoryItemTests.swift`: the fixture is read with `Bundle.module` instead of `Bundle(for: type(of: self))`.
- `MaccyTests/HistoryDecoratorTests.swift`: `testImage` used Maccy's 16-point `StatusBarMenuImage` asset (not taken); it now builds a 16 × 16 bitmap image.
- `MaccyTests/ClipboardTests.swift`: `testIgnoreApplication` and `testIgnoreAllApplicationsExcept` also list the frontmost app's bundle id in `ignoredApps`. Maccy assumed Xcode or Finder is frontmost while tests run, which isn't so under `swift test` from a terminal. (Replaced in task 2 by an injected source app, below.)

#### Stage 4 task 2: isolation and hardening

Behaviour changes, each for privacy or for off-means-off:

- `Maccy/Clipboard.swift`:
  - `static let shared` goes through `ClipKit.track(_:)`.
  - `private let pasteboard = NSPasteboard.general` and the frontmost-app lookup → an injected `ClipboardEnvironment` (pasteboard, source app, Secure Keyboard Entry probe, Accessibility probe). `ClipKit` passes `.general` and the real probes; under a test host the default is a private named pasteboard, no source app, no secure input and no Accessibility.
  - New `stop()`: invalidates the timer, nils it and clears the hooks. `start()` invalidates any previous timer first; `restart()` does nothing unless running. New read-only `pollingTimer`.
  - `checkForChangesInPasteboard()` returns without reading anything when no hook is installed (stopped); skips copies while Secure Keyboard Entry is on; skips Universal Clipboard copies (`com.apple.is-remote-clipboard`) unless `recordUniversalClipboard` is on; skips copies with more than `maxRecordedContents` (1,000) pasteboard items or contents, because SwiftData's insert time grows with the square of the contents (a 10,000-file copy took ~12 s on the main thread).
  - `paste()` posts ⌘V only if the Accessibility probe says trusted; otherwise the item is just copied. It no longer calls `Accessibility.check()`.
- `Maccy/Storage.swift`: `static let shared` goes through `ClipKit.track(_:)`. It opens `Storage.location`, which `ClipKit.start()` sets (`…/Mooring/Clipboard/Storage.sqlite` by default; in memory if `inMemory`, if the folder can't be secured, and always under a test host — `ClipKit` decides, so `Storage` no longer checks the test host), instead of `…/Maccy/Storage.sqlite` built at static init. The `#if DEBUG` test-host check is gone. A store that fails to open logs and falls back to memory instead of `fatalError`. Changing `location` after `shared` opened asserts in debug builds and logs in release; the store stays where it opened.
- `Maccy/Extensions/Defaults.Keys+Names.swift`: the `#if DEBUG` `<bundle id>.uitests` suite trick and `testingSuiteName` are removed; every key uses `UserDefaults.clipKit` (`dev.mooring.clipboard`, or `dev.mooring.clipboard.tests` under a test host). `ignoredApps` defaults to `passwordManagers` (1Password 7 and 8, Bitwarden, Dashlane, LastPass, KeePassXC, Keychain Access, Passwords). New key `recordUniversalClipboard`, default false.
- `Maccy/Extensions/KeyboardShortcuts.Name+Shortcuts.swift`: names are prefixed (`clipboardPopup`, `clipboardPin`, `clipboardDelete`, `clipboardTogglePreview`) so they can't collide in the app's `UserDefaults.standard`, the popup's raw name comes from `ClipKitShortcuts.popupRawValue`, and each is wrapped in `ClipKitShortcuts.guarded`, which unregisters it at creation and after every change unless allowed (the popup hotkey only while running; the other three never, as Maccy's `AppDelegate.disableUnusedGlobalHotkeys` did).
- `Maccy/Observables/Popup.swift`: `init()` no longer calls `KeyboardShortcuts.onKeyDown` or adds the events monitor. New `start()`/`stop()` (called by `ClipKit`) do: the key-down handler is installed once and ignores presses unless started (KeyboardShortcuts 2.0.2 can't remove one handler); the hotkey is enabled and disabled through `ClipKitShortcuts`; `stop()` removes the monitor and closes the panel. `reset()` re-enables the hotkey only while started. `deinitEventsMonitor()` now nils the monitor. New read-only `isStarted` and `hasEventsMonitor`.
- `Maccy/Observables/ModifierFlags.swift`: Maccy added a `flagsChanged` monitor in `init`, capturing `self` strongly and never removing it. The monitor now captures `self` weakly, is added only while ClipKit runs (`setMonitoring(_:)`, called by `start()`/`stop()` for every live instance), and is removed in `deinit`. New read-only `isMonitoring` and `monitoringCount`.
- `Maccy/ApplicationImage.swift`: the four `print` calls (errno and message when an app can't be watched; "Deleted"/"Modified" with the app's path) → `ClipKitLog.logger.debug`, without the path, which would tell which app a copy came from.
- `Maccy/Models/HistoryItem.swift`: the text-recognition `print("Unable to perform the request: \(error).")` → `ClipKitLog.logger.error` with the error's type only.
- `Maccy/Notifier.swift`: `authorize()` and `notify(body:sound:)` do nothing. Maccy posted each copied item's text to Notification Center and asked for notification permission.
- `Maccy/Observables/History.swift`: `static let shared` goes through `ClipKit.track(_:)`. `logger` is `ClipKitLog.logger`. Log lines no longer include item titles ("Inserting item with id '<title>'", "Removing duplicate item '<title>'", and three PasteStack lines); the clear-storage error logs the error's type only. (An unused binding left by that edit became `!stack.items.isEmpty`.)
- `Maccy/Observables/SlideoutController.swift`: `logger` is `ClipKitLog.logger`.
- `Maccy/Observables/AppState.swift`, `Maccy/ApplicationImageCache.swift`: `static let shared` goes through `ClipKit.track(_:)`.

Strings now resolve from ClipKit's bundle (`Bundle.module`) instead of the app's main bundle:

- `NSLocalizedString(…)` gains `bundle: .module` in `HighlightMatch.swift`, `PinsPosition.swift`, `PopupPosition.swift`, `Search.swift`, `SearchVisibility.swift`, `Sorter.swift`, `Observables/HistoryItemDecorator.swift`, `Observables/NavigationManager.swift`, `Views/FooterItemView.swift` and `Views/ToolbarView.swift`.
- SwiftUI: `Text(…, bundle: .module)` in `Views/FooterItemView.swift`, `Views/HistoryItemView.swift` (two accessibility actions), `Views/ListHeaderView.swift`, `Views/PreviewItemView.swift` (five labels), `Views/SearchFieldView.swift` and `Views/ToolbarView.swift`; `Views/ListItemView.swift` `.help(Text(help, bundle: .module))`; `Views/SearchFieldView.swift` `TextField(text:label:)` with the placeholder as a `Text(…, bundle: .module)` label; `Views/ConfirmationView.swift` the dialog title, message and both buttons as `Text(…, bundle: .module)` (buttons via `Button(role:action:label:)`).

Tests:

- `MaccyTests/*.swift` (all ten): the classes inherit `GeneralPasteboardGuardedTestCase` (Mooring's), which fails a test if `NSPasteboard.general`'s change count moves during it.
- `MaccyTests/ClipboardTests.swift`: each test uses its own `Clipboard` on a uniquely named pasteboard (released in `tearDown`, where the clipboard is also stopped), with Xcode injected as the source app, instead of `Clipboard.shared` on `NSPasteboard.general`. The two ignore-app tests are back to Maccy's `ignoredApps` lists.

Mooring-written (not from Maccy):

- `Sources/ClipKit/TestHost.swift`: `TestHost.isActive`, the same test-host check as WindowKit's.
- `Sources/ClipKit/PopupPanel.swift`: `protocol PopupPanel: NSWindow` with `isPresented`, `open(height:at:)` and `verticallyResize(to:)`, the members Maccy's views used on `FloatingPanel`.
- `Sources/ClipKit/ClipKit.swift` (task 2): the public surface: `start()`/`stop()`, `isRunning`, `isPopupShortcutRegistered`, `instantiatedSingletons`/`track(_:)`, the store folder (`0700`, excluded from backup), `ClipItem`, `recent`, `copy`, `paste`, `isPaused`, `ignoreNextCopy`, `clear`, `popupView`, `popupShortcutName`, `defaultStoreURL`.
- `Sources/ClipKit/ClipKitSettings.swift` (task 2): the `dev.mooring.clipboard` suite, and `ClipSettings` with `ClipKit.settingsValues()` / `setSettingsValues(_:)`.
- `Sources/ClipKit/ClipboardEnvironment.swift` (task 2): `ClipboardEnvironment` and `SourceApplication`.
- `Sources/ClipKit/ClipKitShortcuts.swift` (task 2): the one place hotkeys are registered and unregistered.
- `Sources/ClipKit/ClipKitResources.swift` (task 2): `ClipKitLog.logger` and `Bundle.clipKit`.
- `Tests/ClipKitTests/*.swift` and `Tests/ClipKitTests/Support/` (task 2).

#### Stage 4 task 4: the popup

`Maccy/FloatingPanel.swift` is split in two, each file headed `// Adapted from Maccy@c376789: Maccy/FloatingPanel.swift`:

- `App/UI/ClipboardPanel.swift` (Swift 6, in the app): the `NSPanel` itself, with Maccy's style mask, level, collection behaviour, hidden traffic lights, close on losing key (unless an alert is up), `canBecomeKey`, `open(height:at:)` and `verticallyResize(to:)`. Changes: no longer generic over its content, which is `ClipKit.popupView()`; built by ClipKit on each `start()` through `makePopupPanel` and dropped on `stop()`, so it exists only while Clipboard is on; the `onClose` closure and `toggle(height:at:)` are gone (`ClipKitPopup.panelDidClose()` resets the popup; ClipKit's `Popup` toggles); its identifier falls back to `dev.mooring.app`; `isReleasedWhenClosed = false`; the alert check is inlined (`NSApplication.alertWindow` is internal to ClipKit). It conforms to `PopupPanel` with `@preconcurrency`.
- `Packages/ClipKit/Sources/ClipKit/ClipKitPopup.swift`: `public enum ClipKitPopup`, the panel's reach into Maccy's state: the saved size, the corner radius, the opening size, the origin for a popup position, `savePosition(of:)` (Maccy's `saveWindowPosition`), `panel(_:willResizeTo:)` (Maccy's `windowWillResize`, with `saveWindowFrame` inlined), `panelDidMove` (`determinePreviewPlacement`), the live-resize and key/resign-key preview calls, and `panelDidClose()` (the slideout closes and `AppState.shared.popup.reset()`, Maccy's `onClose`). Each does nothing, or only reads settings, until a ClipKit has started.

Vendored edits:

- `Maccy/Views/ListHeaderView.swift`: the title "Maccy" → "Clipboard".
- `Maccy/Observables/Footer.swift`: the "quit" footer item (⌘Q) is removed; it would quit Mooring.
- `Maccy/Observables/AppState.swift`: `openPreferences()` closes the popup and calls the running ClipKit's `openSettings` (Mooring's Settings); `quit()` is removed; new `pasteHint`: "Paste with ⌘V. Allow Accessibility in Windows to paste automatically." while the Accessibility probe says untrusted, else nil.
- `Maccy/Views/FooterView.swift`: shows `pasteHint` under the footer items, read again whenever the popup becomes key or resigns.

Mooring-written:

- `Sources/ClipKit/PopupPanel.swift`: `PopupPanel` is public; `open(height:at:)` takes the public `ClipSettings.PopupPosition` (an internal overload maps Maccy's `PopupPosition`). It stays non-isolated because Maccy's `Popup` calls it from non-isolated code.
- `Sources/ClipKit/ClipKit.swift`: `makePopupPanel` (called in `start()`; `stop()` closes the panel and drops it), `openSettings`, `openPopup()` (opens where the popup-position setting says; nothing while not running or already open), `popupShortcutDescription` ("⇧⌘C"), and the internal `hasStarted`. `recent(limit:includingPinned:)` can leave pinned items out (the dropdown lists only unpinned ones, numbered as the popup numbers them). `confirmAndClear(all:confirm:)`, for the dropdown's Clear and Clear All, keeps the popup's confirmation: it honours `suppressClearAlert`, otherwise asks with `askToClear()`, an `NSAlert` built from Maccy's `clear_alert_*` strings (`Bundle.module`) with a suppression checkbox that sets `suppressClearAlert` when the user confirms; `shouldClear(alertSuppressed:confirm:)` is that rule on its own; `ClearConfirmation` is the answer.
- `Tests/ClipKitTests/PopupTests.swift`, `Tests/ClipKitTests/ClearTests.swift`.

#### Stage 4 final fixes

Mooring-written:

- `Sources/ClipKit/ClipKit.swift`: `discardLoadedHistory()` drops the history a stopped ClipKit loaded earlier in the process (Maccy's `History.clearAll()`), for Settings' "Delete Clipboard History…"; it does nothing while one runs or if none ever started, so it creates no singleton. Tested in `ClearTests` and `IsolationTests.noSingletonsBeforeStart`.

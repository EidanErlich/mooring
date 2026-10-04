# Maccy

- Repo: https://github.com/p0deje/Maccy
- Commit: c376789c5d377b7c520b6f6e91f3f3a1aa28640b (2026-09-04)
- License: MIT (see LICENSE in this folder)
- Used for: the dropdown's floating panel (stage 1b) and clipboard history, vendored as ClipKit (stage 4)

## Files taken

| Upstream file | Mooring file |
| --- | --- |
| `Maccy/FloatingPanel.swift` | `App/UI/FloatingPanel.swift` (stage 1b) |

### Stage 4: ClipKit

Copied as plain files (no git history) into `Packages/ClipKit`, keeping Maccy's folder names:

- `Maccy/<path>` → `Packages/ClipKit/Sources/ClipKit/Maccy/<path>` for the 87 source files listed below.
- `Maccy/en.lproj/Localizable.strings` → `Packages/ClipKit/Sources/ClipKit/Resources/en.lproj/Localizable.strings`.
- `Maccy/Views/en.lproj/PreviewItemView.strings` → `Packages/ClipKit/Sources/ClipKit/Resources/en.lproj/PreviewItemView.strings`.
- `Maccy/Sounds/Knock.caf`, `Maccy/Sounds/Write.caf` → `Packages/ClipKit/Sources/ClipKit/Resources/Sounds/`.
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

- `Intents/` (all six: `AppIntentError.swift`, `Clear.swift`, `Delete.swift`, `Get.swift`, `HistoryItemAppEntity.swift`, `Select.swift`), `SoftwareUpdater.swift`, `AppStoreReview.swift`, `About.swift`, `MenuIcon.swift`, `Settings/` (all panes and their strings; rebuilt later as Mooring's Clipboard pages), `AppDelegate.swift` and `MaccyApp.swift` (wiring reference only).
- `FloatingPanel.swift`: not needed to compile; the views reach the panel through `PopupPanel` (see Modifications). Stage 4 adapts it into `App/UI/`.
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
- `Maccy/Observables/Footer.swift`: removed the "about" footer item (it called `openAbout()`). The "preferences" item stays and, for now, does nothing.
- `Maccy/Observables/Popup.swift`, `Maccy/Observables/SlideoutController.swift`, `Maccy/Views/SlideoutView.swift`, `Maccy/Views/ToolbarView.swift`: `AppState.shared.appDelegate?.panel` / `appState.appDelegate?.panel` → `AppState.shared.panel` / `appState.panel` (seven call sites).
- `Maccy/Observables/History.swift`: removed the unused `import Settings`.
- `Maccy/Extensions/Defaults.Keys+Names.swift`: `AppDelegate.isTesting` → `TestHost.isActive`; removed the `menuIcon` key (its type, `MenuIcon`, isn't taken).
- `Maccy/Storage.swift`: `AppDelegate.isTesting` → `TestHost.isActive`, so the store is in memory under any test host. Maccy keyed this on the `enable-testing` launch argument that its test plan passes.
- `Maccy/Extensions/NSSound+Named.swift`: `Bundle.main` → `Bundle.module` for `Knock.caf` and `Write.caf`.
- `Maccy/Notifier.swift`: `notify(body:sound:)` returns early unless the main bundle is an `.app`. `UNUserNotificationCenter.current()` raises an exception in `swift test`'s bare `xctest` tool, which crashed the test run.
- `MaccyTests/*.swift` (all ten): `@testable import Maccy` → `@testable import ClipKit`.
- `MaccyTests/HistoryItemTests.swift`: the fixture is read with `Bundle.module` instead of `Bundle(for: type(of: self))`.
- `MaccyTests/HistoryDecoratorTests.swift`: `testImage` used Maccy's 16-point `StatusBarMenuImage` asset (not taken); it now builds a 16 × 16 bitmap image.
- `MaccyTests/ClipboardTests.swift`: `testIgnoreApplication` and `testIgnoreAllApplicationsExcept` also list the frontmost app's bundle id in `ignoredApps`. Maccy assumed Xcode or Finder is frontmost while tests run, which isn't so under `swift test` from a terminal.

Mooring-written (not from Maccy):

- `Sources/ClipKit/TestHost.swift`: `TestHost.isActive`, the same test-host check as WindowKit's.
- `Sources/ClipKit/PopupPanel.swift`: `protocol PopupPanel: NSWindow` with `isPresented`, `open(height:at:)` and `verticallyResize(to:)`, the members Maccy's views used on `FloatingPanel`.

# Stage 4: ClipKit (Maccy inside Mooring)

Oct 4, 2026 · Eidan Erlich · Status: built (shipped in 0.1.0)

## Goal

Maccy's clipboard history runs inside Mooring as **ClipKit**, behind the same icon. It has a popup on ⇧⌘C with search, pins, paste and the usual content types, plus a Clipboard submenu and Clipboard settings. It's **off by default**: with Clipboard off, nothing is recorded and no store is created.

**Agents get no clipboard API.** No CLI command, IPC op, MCP tool, App Intent, URL route or AppleScript call reaches the history, and a test fails the build if one does.

## Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Packaging | **`Packages/ClipKit`**, vendored Maccy@`c376789` in Swift 5 language mode (Maccy is Swift 5), following 3a's vendoring rules exactly (headers, `THIRD_PARTY/Maccy/UPSTREAM.md`). | Same pattern as WindowKit. |
| Dependencies | Defaults (the app's exact 9.0.9; Maccy's 8.2 calls are adapted, with every edit listed), KeyboardShortcuts, Sauce, SwiftHEXColors and Fuse at exact versions; swift-log. **Not** Sparkle, Settings or LaunchAtLogin. | SPEC file map. One Defaults version per graph. |
| Settings isolation | Maccy's `Defaults` keys live in the `dev.mooring.clipboard` suite (`dev.mooring.clipboard.tests` under a test host). | Same as WindowKit. |
| Store | SwiftData at `~/Library/Application Support/Mooring/Clipboard/`; directory `0700`; `isExcludedFromBackup`; unencrypted, as Maccy. Created only when Clipboard turns on. Under tests, an in-memory container. | SPEC 4.4. |
| Off means off | A `ClipboardController` (`App/Clipboard/`) owns ClipKit. While off, there's no pasteboard polling, no store and no hotkey registration. Building any ClipKit view while off is avoided, as in 3a. | SPEC 4.7 acceptance. |
| Turning on | Dropdown **Clipboard ›** shows "Turn On…" while off. Turning on needs no permission (recording doesn't). Settings → Clipboard → History has the same switch. | SPEC 4.6. |
| Auto-paste | Uses Accessibility (the 3a grant). Without trust, selecting an item copies it, and a one-line hint in the popup footer says "Paste with ⌘V. Allow Accessibility in Windows to paste automatically." Mooring never prompts from the clipboard. | SPEC 4.6. Prompts belong to Windows' Turn On. |
| Popup | Maccy's floating panel, copied into `App/UI/ClipboardPanel.swift` (SPEC file map), with Maccy's views. ⇧⌘C (configurable via KeyboardShortcuts), registered only while on. | SPEC 4.1. |
| Dropdown | **Clipboard ›**:<br>• while on: the 10 most recent items (title truncated, ⌘-number hints for the first 9), a separator, "Pause Recording" (a toggle), "Ignore Next Copy", "Clear" (unpinned; with ⌥ "Clear All"), a separator, and "Search… ⇧⌘C";<br>• while off: "Turn On…". | SPEC dropdown table. |
| Settings → Clipboard | **History:** on/off, history size (default 200), "Clear history on quit", paste settings and the popup hotkey.<br>**Ignore Rules:** ignored apps, ignored pasteboard types, regexes, and the Universal Clipboard toggle (off).<br>**Appearance:** popup position, pins position, search visibility, preview and image size.<br>These are rebuilt in SwiftUI from Maccy's settings, using only keys ClipKit reads. | SPEC: Maccy's `Settings/` rebuilt as Clipboard pages. |
| Never recorded | Concealed, transient and auto-generated types, always; Maccy's default ignored types; copies while Secure Keyboard Entry is on; ignored apps, with defaults that include 1Password 7 and 8, Bitwarden, Dashlane, LastPass, KeePassXC, Keychain Access and Passwords.app; Universal Clipboard off by default. | SPEC 4.5. |
| Shortcuts page | Gains "Clipboard popup" (with its chord, or a note when Clipboard is off). Conflicts with the Windows trigger and keybinds are flagged. | SPEC 3.7 and 4. |
| Agent wall | `AgentWallTests`, explained below. `NSAppleScriptEnabled = NO` in Info.plist. README states that Mooring protects the history, not the current clipboard. | SPEC 4.3. |
| Removed from Maccy | `Intents/` (6 files), `SoftwareUpdater`, `AppStoreReview`, `About`, `MenuIcon`, `Settings/` (rebuilt), `AppDelegate`/`MaccyApp` (reference only), the `ignoreEvents` defaults switch (replaced by the Pause item), and Maccy's app icon. | SPEC 4.2. |
| Version | 0.0.6. | — |

## The agent wall (tests)

`AgentWallTests` fail if any of the following becomes true:
- **Imports:** any file under `App/IPC/`, `App/Links/`, `App/Intents/` or `Packages/MooringIPC/` imports `ClipKit`, or names `History`, `HistoryItem`, `Clipboard.shared` or `Storage`. Checked by scanning sources.
- **IPC ops:** `Op.allCases` (add `CaseIterable`) contains anything matching `clip|paste|history`.
- **MCP:** the MCP tool list contains anything matching `clip|paste|history`.
- **Intents:** an `AppIntent` type is declared anywhere in `Packages/ClipKit`.
- **AppleScript:** `NSAppleScriptEnabled` isn't `false` in the built app's Info.plist.

## Testing

- **ClipKit (package):**
  - Maccy's tests are copied and pass. They use an in-memory store and the test suite.
  - New tests:
    - `concealedTypesNeverRecorded`;
    - `transientAndAutoGeneratedNeverRecorded`;
    - `ignoredAppNeverRecorded`, for 1Password's bundle id, `com.1password.1password`;
    - `secureInputBlocksRecording`, through an injected secure-input probe;
    - `universalClipboardOffByDefault`;
    - `historySizeDefault200`;
    - `storePathAndPermissions` (in a temp folder: `0700`, excluded from backup).
- **App:**
  - `ClipboardController`: `offMeansNoStoreNoPolling`, `turnOnCreatesStoreAndStarts`, `turnOffStops`, `clearOnQuit`;
  - the dropdown in the off and on states;
  - the Settings pages show only keys that are read;
  - the Shortcuts conflict for the clipboard hotkey;
  - `AgentWallTests`.
- **Performance:** a test builds the popup's item list from 200 fixture items and asserts it takes under 100 ms on a warm run. The live popup timing is checked in the manual check.

## Manual check

1. Leave Clipboard off: no `Clipboard/` folder exists.
2. Turn it on, copy text, an image and a file, then open ⇧⌘C. Search, pin, then paste with ⌥Return. With Accessibility granted it pastes; without, it copies.
3. Copy a password from 1Password: it doesn't appear.
4. Check that `mooring --help`, `mooring mcp` `tools/list` and Shortcuts show nothing clipboard-related.

## Out of scope

- Encryption, and a sandboxed helper. The known limitation stays documented, as in SPEC 4.4.
- iCloud sync of history.

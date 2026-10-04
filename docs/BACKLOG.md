# Backlog

Small issues found in review and deferred. None of them blocked merge. The most user-visible ones are listed first in each section. Delete an item once it's fixed.

## Claude Code plugin (2b leftovers)
- `doctor`'s plugin detail can name the GitHub copy when both copies are enabled and `claude plugin list` lists it first; prefer the app copy explicitly.
- `doctor` still says "not installed" when both `claude --version` and `plugin list` fail; skip whenever the list is unavailable.
- SPEC.md's Esc paragraph says an interrupted turn keeps its lease "up to 15 min"; with renewals that only extend, it can last until a long Bash hold or the waiting timeout ends.
- No tests for the installer failing at `marketplace remove` (must stop before `add`) or at `add` after a successful remove.
- The moved-app check compares standardized paths without resolving symlinks, so a symlinked app path triggers a needless remove and reinstall.
- **Async renew after the sync `Stop`.** An async `PostToolUse`, `PostToolBatch` or `SubagentStop` can land after the sync `Stop` for a very short final reply, which turns the 2 min grace into 15 min.
- **"Only when asked" mid-session** also skips the `Stop` and `SessionEnd` releases, so a lease made just before the switch lives out its expiry.
- **The internal-agent rule** relies on undocumented Claude Code behaviour (a helper agent with an `agent_id` and no `agent_type`). A typed helper agent would renew after every turn.
- **`SessionEnd`'s 1 s hook timeout** is shorter than the 1.5 s reply limit, so Claude can kill the hook before it gives up. Harmless: the watch ends the lease when `claude` exits.
- **A failed `claude plugin list`** still reads "Not installed" on the Settings page (doctor now skips).
- **On timeout, the runner doesn't kill grandchildren** (`ProcessRunner` has no process group).
- **The waiting picker** shows no selection for odd stored values (for example after `defaults write`).
- **`findClaude` and `runBounded` in the CLI are untested.**
- **A skill or hook change must bump the plugin version** (`plugin.json`; it may trail `MARKETING_VERSION` but never lead it). The installed copy is cached by version, so otherwise it keeps the old files and Settings shows no "Needs update".

## Lid approvals (2c-1 leftovers)

- **Agent-granted mark survives menu changes.** If an agent's `on` got lid and you then change that session from the menu, it still counts as agent-granted, so switching to Never takes its lid. Fix: a counter bumped by the menu entry points, stored with the mark.
- **The `claude-` session prefix** is duplicated in `GuardrailNotifier` and `RequestHandler.sessionLeasePrefix`.
- **No test for `AgentDetection.descends`** walking past 64 steps (the cycle case is tested).
- **Agent detection is advisory.** An agent escapes it by detaching itself (`(mooring on --level lid &)` reparents to `launchd`), by launching `mooring` through Terminal or `osascript`, or by naming a binary `claude` to inherit "Always allow Claude Code". It guards against accidents, not a hostile agent.
- **The first-run permission prompt runs outside the 60 s budget:** the timer starts after `authorize()` returns, so the first ask can outlast the CLI's 65 s ("didn't answer") and a later Allow still adds lid.
- **An unwatched hook session under Always ask** can be falsely refused ("the request changed") when it renews during the ask, because "expiry no later" fails after a renewal.
- **Compare the whole watch** (pid and start time) when checking that the request is unchanged, not just the pid.
- **Session acquires on battery** still log a guardrail notice (the notification is skipped).
- **The decision tests** are tables, not a full exhaustive product of every input.

## MCP, links and Shortcuts (2c-2 leftovers)

- The known MCP client names (`claude-ai`, `cursor-vscode`) are unverified until a real `initialize` is recorded.
- **Small leftovers:**
  - `HandlerGateTests` may not exercise the wait path;
  - no `LinkHandler` test for a guardrail not being reported, or for a plain `off`;
  - the `app-` prefix is duplicated;
  - link parameter names are case-sensitive, and `+` isn't decoded as a space;
  - `Doctor.checks` takes 9 parameters;
  - `MCPClientsSection` rebuilds its model on every page render;
  - `Row.name` builds a throwaway config;
  - overlong MCP lines are buffered whole before the 1 MB check;
  - a second `initialize` changes the name the server filters `status` by.
- A config symlink chain that dangles is followed one hop only, so the atomic write replaces the second link with a file; and a relative link target is resolved lexically, which can differ when the link's folder is itself a symlink.


## Windows (3a leftovers)

- **Settings can't be edited before Windows is on.** While off, every Windows page shows only the "Windows is off" banner.
- **The pill clears while the Accessibility sheet is open** after trust was revoked, because the state moves from needsAccessibility to waitingForTrust.
- **Loop's other pages weren't checked for controls that do nothing** in Mooring (only Launch at login, Start hidden and Hide menu bar icon were removed). A missing settings window shows a blank page, and the page padding is indented oddly.
- **Stash isn't fully gone.** `StashManager.shared` is still created during a Loop session (it does nothing), a Stash binding that already exists can still open its settings view, and the `windowDetails` capability is one switch for several features.
- **Shortcuts page:** the fn and Caps Lock (⇪) modifiers aren't handled the same way everywhere; letter labels follow the ASCII layout, not the keyboard layout; the layout tests only check sizes.
- **No live preview on the hosted pages.** Loop's settings window shows a live radial menu and preview beside its pages; Mooring hosts the pages without it, so changes on Radial Menu and Preview show no preview.
- **Loop and Mooring share one defaults registration.** `Defaults` registers defaults in the process-wide registration domain. No key names collide today (Loop's 76, Mooring's 5); a test checking the names would keep it that way.
- **Tests:**
  - `submenuFollowsTheStateWhileOpen` depends on `Task.yield` timing and may flake on CI;
  - `offMeansOff` counts WindowKit singletons process-wide, so a later app test that builds a real WindowKit must run serially;
  - the WindowKit start/stop tests start real managers.
- **WindowKit code:**
  - the `runningOwner` identifier is never cleaned up when its owner goes away;
  - `ScreenSwitchFrames.frame(for:)` is used only by tests;
  - the `PrivateApis.swift` header still talks about `@_silgen_name`;
  - the `WindowsController` live pieces could move to their own file.
- **Build noise and docs:** the vendored code gives deprecation warnings (macOS 13 to 14) and an upstream `swiftui-introspect` manifest warning; the Scribe comment in `Packages/WindowKit/Package.swift` says `Package.resolved` fixes the revision, but the app's pin is `Config/Package.resolved`; `UPSTREAM.md` words the test-suite condition for Loop's settings loosely (the code checks `XCTestConfigurationFilePath`).
- `gesturesAvailable` sits between `menuActions(primary:)` and its doc comment, so the comment attaches to the wrong declaration.
- `everyLoaderSymbolIsChecked` doesn't include the MultitouchSupport symbol list.
- Turn On without Accessibility shows macOS's own Accessibility alert alongside Mooring's sheet; confirm in the owner check that this reads well.


## Agent windows (3b leftovers)

- **A just-launched app** with no window yet reports `not_found` rather than "didn't open in time".
- **Left and right screens** are picked by the screen's right edge, which can prefer a diagonal screen over the true neighbour.
- **Layouts:** a layout saved with an exact title breaks when that title changes.
- **App search** scans the top level of the Applications folders only.
- **Results:** `WinStatus` has no fallback for a status a newer app might send; the folded region-name uniqueness is untested; `partial` ignores position clamps, so an off-position window can report `ok`.
- **Accessibility timeouts:** setting the timeout (process-wide and per element) ignores its error.
- **Gating:** a request that started under Automatic isn't asked if agents switch to Ask first while it waits its turn (Off and Windows off are checked again).
- **Regions:** `win do` refuses minimize, hide, Space moves and the other non-frame actions for people too, since `win.*` offers only frame regions; the Windows menu still has them.
- **Matching:** two instances of one app give identical candidate names; a result from an older app without an ambiguous `reason` prints "matches several: …".
- **CLI:**
  - the message for a plan that can't be decoded at the root path ends in a dangling "at";
  - the plan file is read before the size cap is checked;
  - `CommandRunner` has a speculative undo rewrite;
  - error prefixes are mixed;
  - the root `mooring --help` doesn't list `win`.
- **MCP:** the "Unexpected reply" text is hard-coded with a default branch, and the undo or-pattern and the path helper are hard to read.
- **Code and tests:** a dead `.launch` branch and a catch-all in the Arranger; test temp folders and a lingering task are not cleaned up; `FakeNotificationPoster` ignores the category, so there is no cross-category withdraw test; the unsigned-build helper warning in the test log is environmental.
- The process-wide 1.5 s Accessibility timeout set when Windows starts isn't reset when it stops.
- The ask notification sanitizes app and title but shows `region` and `screen` as sent.


## Clipboard (4 leftovers)

- **Shortcut text:** `KeyboardShortcuts`' own rendering of Space and the F-keys may not match `ShortcutChord`'s forms ("␣", "F11"), so the Shortcuts page could miss a conflict with Spotlight or another macOS shortcut for the clipboard chord. Check it against the keys macOS reserves.
- **Tests:**
  - wall-clock performance thresholds may flake on CI, and the popup performance test measures load plus `recent`, not row rendering;
  - `offMeansNoStoreNoPolling`'s real-singleton line can't fail with the fake, so its comment overstates it, and `turnOffUnregistersHotkey`'s name overstates what it checks;
  - the read-only-parent store test assumes the tests don't run as root;
  - the Settings tests include a Finder-dependent case;
  - nothing tests that `AppDelegate` passes `showClipboardHistory` to `ClipboardController.live`.
- **ClipKit code:**
  - `History.load`'s task isn't cancelled on stop;
  - `ModifierFlags`' `deinit` and statics aren't main-actor isolated (theoretical);
  - after **Delete Clipboard History…** in a session where Clipboard already ran, the SwiftData store stays open on the deleted file (it can't reopen in-process), so if Clipboard is turned back on before Mooring restarts, that session's copies aren't saved to disk and an empty `Clipboard/` folder is recreated.
- **Settings pages:**
  - `ClipboardOnPage` builds a model on every parent re-render, and the model caches values;
  - `@_exported import KeyboardShortcuts` in ClipKit stands in for linking it from the app;
  - the ignored-app picker removes ".app" with `replacingOccurrences` and silently does nothing for a bundle with no id;
  - the preview delay isn't exposed ("Ignore all apps except listed" is hidden on purpose, SPEC 4.8).
- **Agent wall:**
  - the parenthesis matcher ignores parentheses inside strings and comments, and trailing closures;
  - there is no `OSAScriptingDefinition` key check in `Info.plist`;
  - the scan reads Swift source text only, not non-Swift files or linked symbols; the `Metadata.appintents` check reads the test host's build and skips if there is none;
  - hardening idea: also assert the app declares no `NSServices` in `Info.plist` and donates nothing to Core Spotlight (`CSSearchableIndex`), two more routes by which history could leave the app.
- **Owner checks, not yet done:** a copy from the real 1Password never appears; the popup opens in under 100 ms with 200 items; the Clear alert over the dropdown, and the popup's placement and footer hint (now refreshed when the popup becomes key); holding ⌥ in the open Clipboard submenu swaps Clear for Clear All (the rows are hosted SwiftUI views, and only the `isAlternate` setup is unit-tested); Delete Clipboard History… removes the folder.

## Release (5 leftovers)

- **Uninstall:** stopping the socket server as step 0 would be tidier, so an agent can't take a new lease while the uninstall runs. It isn't needed for safety: `LidController.apply` refuses to disable sleep once shutdown has begun, and assertions die at quit.
- **Uninstall scope:** a Claude plugin installed from GitHub (`mooring@mooring`) is left installed, by design. The in-app CLI step removes only a link to this app's own bundled `mooring`, while `make uninstall` removes any link under `/Applications/Mooring.app/`.
- **Uninstall tests:** `make uninstall`'s refusal guard in `scripts/test-make-uninstall.sh` can't fire (isolation comes from the overrides, which is sound); the test log shows "Unable to find service status" noise that predates stage 5.
- **Updater:** the misleading `#require` message in `ClaudePluginFilesTests`.
- **Release script:** a real (non-dry) run was never exercised end to end by an agent: it needs the owner's signing identity and Sparkle key. `sign_update` was never run, and `shellcheck` wasn't available (only `bash -n`). The key and signature checks, and the check of `origin`'s tags, are tested with fixtures and shimmed `make` and `git`.
- **Owner checks, not yet done:**
  - Sparkle keys (and the offline backup), `bash scripts/release.sh --publish` and a look at the `dist/` it built (`docs/RELEASING.md`);
  - with the owner's identity, the embedded Sparkle.framework still passes `codesign --verify --deep --strict` after Xcode re-signs it;
  - a clean install on a second user account: the Gatekeeper block, **Open Anyway** and the `xattr` fix, and the first-launch update consent;
  - **Uninstall Mooring…** on a real install, including that `claude plugin marketplace remove mooring-app` (which also uninstalls the plugin) reads right;
  - the tap repo, Pages and the printed publish commands (the first one tags `v0.1.0`);
  - with 0.1.1: a scheduled update found while Mooring is in the background posts the notification and shows **Update Available…**, and the update replaces a bundle whose helper is running.

## CLI and IPC (stage 2a leftovers)

- **Re-acquire edge cases (from the 2b-prep fixes):**
  - re-acquiring a lease whose watched process just died fails with "Process N isn't running", even when only `--ttl` was given;
  - a pre-`ttl` lease re-acquired with `--ttl 60` gets a 60 s renew length.
- **Small code and test leftovers:**
  - `Plan.reasonGiven` duplicates the handler's `cleaned(_:)`;
  - the `blocked` socket test returns early as root instead of using `.enabled(if:)`;
  - there's no test for `anchor -- cmd --json` keeping anchor's own errors human, or for the ttl after a longer re-acquire.

- **`doctor`:** a transient lid-sleep mismatch can show during a helper call.
- **"End my session after the Mac sleeps"** now also ends a CLI `on`, which follows from the one-switch decision. Note it in the release notes.
- **A Terminal-started menu session** shows the reason "Turned on from the menu bar".
- **`anchor`:**
  - Hardening: a microsecond gap between spawn and forwarding (pre-install `SIG_IGN` plus `POSIX_SPAWN_SETSIGDEF`), and a pid-reuse window in `wait()`.
  - SIGQUIT isn't handled.
- **Robustness:**
  - Unknown client errors drop the underlying error.
- **Display:**
  - `p_comm` truncates process names to 16 characters.
  - `status` columns count characters, not display width.
- **Socket server:**
  - `withDeadline`'s timer lives the full second on success.
  - There's no total per-connection deadline after the read.
  - There's no `deinit` guard if the server is released without `stop()`.
- **Wire format:**
  - `Request` can pair a mismatched op and args.
  - The `Response` memberwise init allows `ok:true` with no result.
  - There's an unused date strategy in `decodeRequest`.
  - There's a `CodingUserInfoKey` force unwrap.
  - Some SwiftLint disables lack a reason.
- **Engine and policy:**
  - A renew no-op looks like a real renewal.
  - Reserved ids are string literals mirroring the engine constants; add a drift test.
  - Tests use magic numbers instead of `maxLeaseLength` / `maxNamedLease`.
- **`CLI/main.swift`'s comment** says "flushes"; the writes are unbuffered.
- **Test gaps:**
  - shorten to the past followed by a tick;
  - a TTL round trip;
  - renewing an expired, not-yet-ticked lease;
  - an anchor with a TTL;
  - no flags, no session and a guardrail together;
  - a dangling or relative symlink, and a parent that is a file;
  - EOF without a newline, and EAGAIN on write;
  - several lease-row changes in one sync;
  - `statusListsOnlyLiveLeases` doesn't prove it uses the injected clock.

## Dropdown menu (from #6)

- **Highlight:** `highlightedID` is shared across submenus, so a submenu closing can leave a stale highlight or wipe it.
- **Keyboard:** arrow keys stop on switch and lease rows, which draw no highlight. Return on a hosted row does nothing.
- **Width:** a long "While … run" title can widen the menu past 300 pt, and Awake uses three different text insets.
- **Status header:** it doesn't shrink back when the countdown shortens the line.
- **Code:**
  - `show(_:)` has no re-entrancy guard;
  - the pending lid action isn't cleared when the menu opens;
  - `StatusItemController.button` is dead code;
  - the ClickRouter test name is stale;
  - there's an unused `import SwiftUI` in `DropdownModel.swift`;
  - lease-row sync has an unreachable "move" branch, and builds and strips "lease." strings.
- **Tests:** no expiry-while-open test, and the 300 pt check skips the header.
- **Docs:** the native-menu design spec header still says "awaiting owner review".

## Stage 6 leftovers

Found while hardening v0.1 and deferred. Still deferred from before, as the stage 6 spec's "Not in this stage" says: WindowKit's `appBuild` (reads `CFBundleVersion` as an Int; now always nil and unused, but vendored, so a re-fetch restores it), accessory apps (menu-bar-only, no Dock presence) left out of `win list` so they can't be arranged, and `mooring mcp` handling one request at a time, so an approval wait (up to 60 s) blocks that client's other calls.

- **Lid approvals:**
  - an agent's `on --level system|display`, or an `anchor` without lid, over a person's lid lease still replaces the level (it isn't a refused or asked path);
  - a deny or timeout after asking about a person's lease gives no "unchanged" hint, and policy errors come after a person-lid refusal;
  - `AwakeEngine.acquire` keeps `createdAt` when it replaces an expired, not-yet-ticked lease; give it a fresh one.
- **CLI:**
  - `--no-launch` doesn't consult the app-running check, so a busy app reads "isn't running" there;
  - `node --require <file>` before the script isn't recognised as Claude Code;
  - each process lookup allocates a 1 MB `KERN_PROCARGS2` buffer;
  - no MCP test that `busy` isn't reported as lost.
- **Settings:**
  - Copy config isn't gated on a transient bundle;
  - an install on an external volume (`/Volumes/…`) reads as transient;
  - `.notALink` shows "Reinstall" (disabled) for something never installed;
  - `ensureCLILinked` has no transient guard of its own (only the install path reaches it).
- **Dropdown and socket:**
  - hosted rows' countdown titles update per sync, not per second;
  - VoiceOver may read switch rows twice (an owner check);
  - a pre-existing Sendable warning at `DropdownMenu.swift:131`;
  - `SocketServer.stop()` doesn't reset the accept back-off's episode flag.
- **Notify:** the rate limit counts a post that wasn't shown.
- **Small leftovers:** `CLIInstaller.install`'s doc comment still says "regular file" (it also refuses a folder); no test decodes an older status without `agentSessionLid`; `SocketServer` tests don't assert stop-while-suspended explicitly; an image's data is read on the main thread before text recognition (a file read for a Universal Clipboard image).

# Mooring — Mac Awake Utility Spec

Sep 29, 2026 · Eidan Erlich

> **For coding agents:** this file is the complete spec for Mooring. Read all of it before starting. Build only the stage you are assigned (see "Build brief for agents" → Stages) and stop at that stage's owner checkpoint. Where sections disagree, "Engineering decisions (authoritative)" wins, then "UX: one icon, one dropdown", then earlier sections. Upstream repos are pinned in "Vendoring".

## Overview

Mooring is one free, open-source macOS menu-bar app that keeps a Mac awake, including with the lid closed, with no password prompt after a one-time approval. It is built in four levels, each shippable on its own:

1. **Core awake** — Chai's idle/display-sleep prevention and Awayke's lid-closed mode behind a single menu-bar icon.
2. **CLI and agents** — a `mooring` command, Claude Code hooks, and an MCP server so agents keep the Mac awake exactly while they work.
3. **Windows** — Loop's radial menu, keyboard actions and cycles.
4. **Clipboard** — Maccy's searchable history, never reachable by agents.

The name is **Mooring** (decided 2026-09-29; checked clear on GitHub, Homebrew and the Mac App Store). Bundle ID prefix: `dev.mooring`; CLI command: `mooring`. "Anchor" is the verb for keeping the Mac awake until a process or agent finishes

### Goals

- One icon, one click, for every kind of keep-awake. The user never needs to know which macOS sleep path is involved.
- No password after first run. Lid mode uses a signed privileged helper approved once in System Settings.
- It can never leave the Mac stuck awake: every awake request expires, and a crash restores normal sleep.
- Agents and scripts drive the same engine the menu does, through a stable CLI.
- Private by default: no network access except an opt-in update check, no telemetry.

### Non-goals

- Replacing Raycast or Alfred as a launcher.
- App Store distribution. The sandbox blocks the root helper, which is why Awayke ships outside it too.
- Windows, Linux, or Intel-only optimisations. Universal binary, but Apple Silicon is the test target.
- Syncing clipboard history across devices.

### Source repos

All four were cloned and read on 2026-09-29. The license column decides what can be copied.

| Repo | Brings | License | Min macOS | Size and stack | Reuse plan |
| --- | --- | --- | --- | --- | --- |
| [Awayke](https://github.com/daemonphantom/Awayke) | Lid-closed awake via `pmset disablesleep`, SMAppService root helper, lid monitor, battery auto-off, crash recovery | MIT | 13 | \~12 Swift files; AppKit + IOKit; signed and notarized release workflow | Copy and adapt the helper, `LidMonitor`, `AutoOffPolicy`, `LidSessionTracker`, release workflow |
| [Chai](https://github.com/lvillani/chai) | Idle and display sleep prevention via an IOKit power assertion; 30 min to 8 h or forever; disable after wake; launch at login | GPL-3.0-only | 14 | 4 Swift files; SwiftUI `MenuBarExtra` | Reimplement (about 40 lines). Don't copy its Glyphish icons: they're licensed for Chai only |
| [Loop](https://github.com/MrKai77/Loop) | Radial menu, trigger key, \~50 window actions, cycles, preview, stash, `loop://` URL scheme | GPL-3.0 | 13 | \~180 Swift files; Defaults, Luminare, Scribe; SkyLight private APIs | Vendor as a module in level 3 |
| [Maccy](https://github.com/p0deje/Maccy) | Clipboard history, fuzzy search, pins, ignore rules, paste | MIT | 14 | SwiftData; Defaults, KeyboardShortcuts, Sauce, Sparkle | Vendor as a module in level 4; strip its App Intents |

**License decision:** vendoring Loop makes the whole app GPL-3.0. Chai adds nothing either way because its code is small enough to rewrite. Recommendation: license the monorepo **GPL-3.0-only** and keep MIT notices on the Awayke and Maccy code. The alternative is to rewrite window management from scratch and stay MIT, which is roughly 5x the work of level 3.

The minimum OS is **macOS 14 Sonoma**, set by Maccy's SwiftData use; everything else supports 13.

### Monorepo layout

```
mooring/
  project.yml            # XcodeGen spec (the .xcodeproj is generated, gitignored)
  Makefile
  Config/                # Shared.xcconfig, Local.xcconfig.example (Local.xcconfig gitignored)
  App/                   # menu-bar app target: Sources/, UI/ (DropdownMenu), Helper/HelperClient.swift, Assets.xcassets, Info.plist
  Helper/                # privileged launchd daemon: main.swift, Shared/MooringHelperProtocol.swift, plists
  CLI/                   # `mooring` executable, incl. `mooring mcp` (stdio MCP server)
  Packages/
    AwakeKit/            # Package.swift, Sources/AwakeKit/, Tests/AwakeKitTests/ (level 1)
    MooringIPC/          # socket wire format shared by app and CLI (level 2)
    WindowKit/           # vendored Loop (level 3)
    ClipKit/             # vendored Maccy (level 4)
  Integrations/
    claude-code-plugin/  # .claude-plugin/plugin.json, hooks/hooks.json, scripts/mooring-hook, skills/mooring/SKILL.md, mooring.json
  scripts/               # write-helper-requirement.sh, lid-kill-test.sh, …
  THIRD_PARTY/<Repo>/    # upstream LICENSE + UPSTREAM.md (provenance)
  docs/SPEC.md           # this spec
  .github/workflows/     # build + unit tests
```

Each vendored package records its upstream commit in `THIRD_PARTY/<Repo>/UPSTREAM.md` so upstream fixes can be ported by hand later.

### At a glance

```
 Callers:  [Menu-bar icon]   [mooring CLI]   [Claude Code hooks]   [MCP server]
                 |                 \                 |                 /
                 |            Local socket (your user only, no clipboard operations)
                 |                   |                         :
                 v                   v                         : (mooring win)
 Mooring.app (runs as you):  [AwakeEngine: leases, guardrails,    [WindowKit: Loop,   [ClipKit: Maccy,
                              reconciler, IOKit assertions]        opt-in, needs AX]   opt-in, no agent API]
                                     |                                                        |
                                     | lid mode, XPC                                          v
                             [Mooring Helper (root):                                  [History store:
                              pmset disablesleep 0/1 only,                             SwiftData, as in Maccy]
                              only the signed app connects]
```

The menu, CLI, hooks and MCP server all end in the same lease engine; only the app talks to the root helper, and nothing outside the app can reach clipboard history.

## UX: one icon, one dropdown

Mooring is one menu-bar icon: a left click turns On with the user's defaults, a right click opens a dropdown with Awake, Windows and Clipboard sections, Settings and Quit. This section takes precedence over 1.3, 1.4, 1.9 and 3.2 wherever they differ.

### Clicking the icon

| Gesture | Does |
| --- | --- |
| Left click | Toggle **On** / Off using the configured On defaults (Chai-style one click) |
| Right click or Control-click | Open the dropdown |
| Global hotkey (configurable) | Toggle On / Off |
| ⇧⌘C | Open the Clipboard popup (Maccy's panel) with search focused; registered only while Clipboard is on |

Settings → General can swap left and right click for people who want the dropdown on click.

**What On means** is set in Settings → Awake → "When I click the icon": level (system, screen on, or lid), duration (until turned off, or 30 min to 8 h), and "end after the Mac sleeps". Defaults: system level, until turned off.

**Icon states** (redesigned 2026-10-01; full design in `docs/superpowers/specs/2026-10-01-menu-bar-icon-design.md`):

| State | Icon |
| --- | --- |
| Off | Dimmed outline anchor |
| Awake | Solid pill: anchor, an inverted **LID** tag while lid sleep is actually disabled, and one kind label for the lease that ends last: `1:12` / `42m` (timed), ▶ (a task: an app, command or agent), ∞ (until turned off) |
| Attention | Orange pill with a white **!**: a guardrail paused something, or lid mode waits on helper approval |

Small badges are not used: at menu-bar size they don't read. Settings → General can hide the countdown.

### The dropdown is a real menu

The dropdown is an `NSMenu` opened from the status item. Native items are used where AppKit has the control, and SwiftUI views hosted in menu items (`NSMenuItem.view`) are used for the live rows: switches, ✓ rows, countdowns and ✕ buttons. Each section is a submenu. A real menu is what keeps an auto-hidden menu bar shown while it is open, which a floating panel can't do (decided 2026-10-01). The Clipboard search field moves to the Clipboard popup, which is Maccy's own panel (stage 4).

```
 ● On · lid mode · 1h 12m left          hosted, live
 ─────────────────────────────────
 Awake                            ›     submenu
 Windows                          ›     submenu
 Clipboard                        ›     submenu
 ─────────────────────────────────
 Settings…                       ⌘,
 Quit Mooring                    ⌘Q
```

| Section | Contents |
| --- | --- |
| **Awake** | On toggle; durations (30 min, 1 h, 2 h, 4 h, 8 h, until turned off); until I open the lid; while an app is running…; keep screen on; allow lid close (on battery: confirmation the first time); **Anchored** list of every lease with owner, reason, time left and ✕ |
| **Windows** | The most-used actions with their shortcuts (halves, maximize, centre, next screen), More Actions, saved layouts (later), Window Manager on/off |
| **Clipboard** | While off, **Turn On…**. While on, a submenu with the 10 most recent unpinned items, Pause Recording, Ignore Next Copy, Clear (Clear All with ⌥), and "Search… ⇧⌘C", which opens the Clipboard popup (4.8) |

A module that's off shows a single **Turn On…** item that walks through its permission (Accessibility), so the dropdown keeps the same shape.

Hosted rows stay 300 pt wide, and clicking one doesn't close the menu, so the ✓ marks, switches and icon update in view. Choosing a native item closes it.

### Settings window (Loop-style sidebar)

| Group | Pages |
| --- | --- |
| General | General, Icon & Appearance, Shortcuts |
| Awake | Keep Awake (On defaults), Lid & Battery, Agents |
| Windows | Behavior, Keybinds, Gestures, Radial Menu, Preview, Excluded Apps |
| Clipboard | History, Ignore Rules, Appearance |
| Mooring | Advanced, About |

The structure mirrors Loop's settings (Theming / Settings / Loop groups with Icon, Accent Color, Radial Menu, Preview, Behavior, Keybinds, Gestures, Advanced, Excluded Apps, About).

## Part 1: Core app (Chai + Awayke in one icon)

Level 1 ships a menu-bar app whose single icon covers both sleep paths: power assertions for idle and display sleep (no admin), and `pmset disablesleep` through a root helper for lid close (one-time approval, then no prompts).

### 1.1 The two sleep paths

| Path | What triggers sleep | How Mooring blocks it | Privilege |
| --- | --- | --- | --- |
| Idle system sleep | No input for the Energy setting's timeout | `IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep)` | None |
| Idle display sleep | Display timeout | `kIOPMAssertPreventUserIdleDisplaySleep` (Chai uses the older `NoDisplaySleepAssertion` name) | None |
| Lid close (clamshell) | Lid switch, no external display | `pmset -a disablesleep 1` | Root, via helper |

Assertions are released by the kernel automatically when the process dies, so the no-admin path is self-cleaning. `disablesleep` is a persistent system setting, so the lid path is not; section 1.6 covers how Mooring guarantees cleanup.

### 1.2 Leases: the one engine

Every request to stay awake, from the menu, a timer, the CLI or an agent, is a **lease**. The Mac stays awake while at least one lease is live. This replaces Chai's single on/off flag and Awayke's intent/override flags with one model.

A lease has an id, an owner, a reason shown in the dropdown, a level, an optional expiry, an optional watched process, and an "ends when the lid opens" flag. The exact Swift types and lease ids are in Build brief → Engineering decisions → Core types.

**Levels** are independent flags on top of idle-system-sleep prevention (exact types in Build brief → Engineering decisions):

- `system`: prevent idle system sleep; screen may turn off. The default for agents.
- `display`: also keep the screen on. Chai's behaviour.
- `lid`: also survive lid close. Awayke's behaviour; needs the helper.

**Reconciler.** One `@MainActor` `AwakeEngine` holds the lease table and, on every change and every 5 s tick, computes the effective level as the union (per-flag OR) over live leases. It then makes reality match: create or release the two assertions, and call the helper to set `disablesleep` to 1 or 0. It diffs against what it last applied so it never calls the helper redundantly. All state changes go through this one function, which makes it easy to test.

**Expiry.** Expired leases are dropped on the tick. PID-watching leases use a `DispatchSource.makeProcessSource(.exit)` so they release instantly, with the tick as a backstop.

**Persistence.** The lease table is written to `~/Library/Application Support/Mooring/leases.json` on every change. On launch, leases that are still in date and whose watched PID is still alive are restored; the rest are dropped.

### 1.3 Modes offered in the menu

| Menu item | Lease created |
| --- | --- |
| Click icon (primary action) | Toggles the "menu" lease at the user's default level and duration |
| For 30 min / 1 h / 2 h / 4 h / 8 h / Until turned off | `menu` lease with `expiresAt` (Chai's durations); replaces any picked apps |
| Until I open the lid | `lid` lease, `endsOnLidOpen = true` (Awayke's `LidSessionTracker`) |
| While an app runs… | Pick one or more running apps (✓ marks each; clicking again un-picks); one `app-<pid>` lease with `watch` per app, replacing the duration. The row reads "While Xcode runs", "While Xcode and Safari run" or "While 3 apps run" |
| Keep screen on | Toggles `display` on the menu session (the `menu` lease or every picked app) |
| Allow lid close | Toggles `lid` on the menu session; until the helper is approved, this row is replaced by "Approve lid mode…", which calls register() and then opens Login Items & Extensions |

Defaults for a fresh install: click = `system` level, until turned off, lid off. Users who want Awayke-style one-click lid mode set the default level to `lid` in Settings.

### 1.4 Menu-bar icon and menu

Icon, click behaviour and dropdown contents are specified in **UX: one icon, one dropdown** above. In short: an anchor icon, outline when off and filled when on; left click toggles On with the user's defaults; right click opens the dropdown; the Awake section lists every active lease with its owner, reason, time left and ✕.

### 1.5 No password after first run: the privileged helper

The helper is a launchd daemon registered with `SMAppService.daemon(plistName:)` (macOS 13+), as Awayke does. First use of lid mode calls `register()`; macOS shows a notification, and the user approves it once in **System Settings → General → Login Items & Extensions**. From then on toggles are silent, across reboots. There is no osascript password fallback: if the helper isn't approved, the menu shows a single "Approve lid mode…" item that opens that pane.

**Helper surface (the whole of it):**

```swift
// Helper/Shared/MooringHelperProtocol.swift, compiled into both the app and the helper
@objc protocol MooringHelperProtocol {
  func setLidSleepDisabled(_ disabled: Bool, reply: @escaping @Sendable (NSError?) -> Void)
  func lidSleepDisabled(reply: @escaping @Sendable (Bool, NSError?) -> Void)  // reads `pmset -g` SleepDisabled; error set if the read fails
  func heartbeat(reply: @escaping @Sendable (Bool) -> Void)   // every 30 s while lid mode is on (1.6); replies with the current SleepDisabled
  func version(reply: @escaping @Sendable (String) -> Void)
}
```

`heartbeat` replies with the real `SleepDisabled`, and a heartbeat that finds it `1` hands ownership back to a helper that restarted (`SleepDisabled` persists; only the helper's memory of having set it is lost). The app sends one at once whenever it starts heartbeating, so its watchdog covers a crash right away.

It runs `/usr/bin/pmset` with a fixed argument array; no strings from the client reach a shell. Target size is under 250 lines of code, not counting comments and blank lines (183 at stage 1c), with no dependencies, so anyone can audit it.

**Caller validation.** Awayke embeds an `SMAuthorizedClients` requirement in the helper's Info.plist but its listener accepts every connection. Mooring enforces it:

- `listener.setConnectionCodeSigningRequirement(req)` (macOS 13+), where `req` is `identifier "dev.mooring.app" and certificate leaf = H"<SHA-1 of the app's signing certificate>"`. The system evaluates it against the connecting process's audit token and drops any other caller before the helper's code runs (observed 2026-09-30: "Dropping check-in message due to code signing requirement", status -67050). A build script writes the requirement into the helper's embedded `SMAuthorizedClients` (Build brief → Engineering decisions), and the helper reads it back from there at launch. Only the signed Mooring app can connect; the CLI and MCP server never talk to the helper directly.
- If no valid requirement is embedded (unsigned or ad-hoc builds), the helper refuses every connection.
- The app and the helper are built with the hardened runtime, so a process running as the user can't inject code into the genuine app (for example with `DYLD_INSERT_LIBRARIES` or a swapped library) and borrow its signature to pass the check. Debug builds also carry `get-task-allow` so a debugger can attach; only Release builds are held to this guarantee.
- A second, manual audit-token check in `shouldAcceptNewConnection` was dropped (decided 2026-09-30): `NSXPCConnection` has no public audit-token API on macOS 26, and the listener requirement above already performs that check.

### 1.6 Never stuck awake

`disablesleep` survives a crash, so cleanup can't live only in the app. Four layers:

1. **Helper watchdog.** The helper records whether it set `disablesleep 1`. When the app's XPC connection invalidates (quit, crash, force-kill), the helper waits 3 s for a reconnect (decided 2026-10-01, for snappiness: a crashed app is never back sooner, and a relaunched app re-applies lid mode itself), then sets it back to 0 on its own.
2. **App heartbeat.** While lid mode is on, the app pings the helper every 30 s. No ping for 90 s → the helper restores sleep. This catches a hung app whose connection is still open. Both are checked every 1 s on the helper's serial queue, which also runs every `pmset` write, so a restore never races a client request; the helper only restores sleep it disabled itself (stage 1c). The helper records ownership in a root-owned marker (`/Library/Application Support/Mooring/helper-owns-sleep`), starts at boot (`RunAtLoad`), and if it owns a `SleepDisabled = 1` at start it waits the same 3 s for the app before restoring; it also restores on the SIGTERM launchd sends for unregister, logout, `kickstart -k` and shutdown (stage 1c). If the app's helper connection drops (the helper restarted), the app re-checks `SleepDisabled` at once instead of waiting for the next heartbeat; helper calls time out after 3 s.
3. **Launch reset.** On launch the app asks the helper for the current value and resets it to 0 unless a restored lease needs lid mode (Awayke does the reset unconditionally).
4. **Quit and uninstall.** `applicationShouldTerminate` restores sleep (waiting up to 3 s). "Uninstall helper…" in Settings restores sleep before calling `unregister()`.

### 1.7 Guardrails (enforced by the engine, not callers)

| Guardrail | Default | Behaviour |
| --- | --- | --- |
| Low battery, lid mode | On battery and < 20% | Suspend `lid` (keep `system`), notify; resume when back on AC and ≥ 25% (Awayke's hysteresis) |
| Low battery, all awake | On battery and < 10% | Suspend all leases, notify |
| Thermal | `ProcessInfo.thermalState` ≥ `.serious` while lid is closed | Suspend `lid`, notify; resume at `.nominal` |
| Lid mode on battery | Allowed, opt-in | Until the user opts in, lid mode applies only on AC. The first lid session on battery shows a confirmation sheet (battery drain, heat, keep it out of bags) with "Allow on battery". While it runs on battery the icon shows the normal LID pill (battery state is left to macOS's battery icon; menu-bar icon redesign, 2026-10-01). |
| Max lease length | 12 h for any lease with an expiry; "Until turned off" allowed only from the menu | Longer requests are clamped and the clamp is reported to the caller |
| Agent cap | 4 h per agent lease, renewable | See Part 2 |

The two lid-mode notifications ("Lid mode paused" at low battery, and "Lid mode waits for power" before the battery opt-in) are posted only when some lease that wants lid isn't a Claude Code session lease (`claude-…`): a session wants lid on every turn, so a session alone would bring one on nearly every prompt. The guardrails still apply to sessions, and "Mooring paused" and the thermal notice are unchanged (stage 2c-1 fixes).

macOS still forces sleep at critical battery regardless of `disablesleep`; the guardrails act before that point. Battery state comes from `IOPSNotificationCreateRunLoopSource` (Awayke's `BatteryMonitor`), lid state from the `IOPMrootDomain` clamshell notification (Awayke's `LidMonitor`).

### 1.8 System events

- **Wake from sleep:** if "End my session after the Mac sleeps" is on (Chai's "disable after suspend"), end the menu session. Agent leases are unaffected.
- **User switch / screen lock:** leases continue. Screen lock is expected in lid mode.
- **External display connect/disconnect:** no change needed; clamshell with a display already stays awake, and `disablesleep` covers the no-display case.

### 1.9 Settings window

Settings use the sidebar defined in the UX section, with the mapping in Build brief → Engineering decisions → UI details. Level 1 needs: launch at login (`SMAppService.mainApp`), click action and left/right swap, On defaults (level, duration, "End my session after the Mac sleeps"), helper status with approve and uninstall, lid-on-battery opt-in, battery thresholds, thermal cutoff, notification toggles, log level, reveal logs and export diagnostics. Values are stored with the `Defaults` package. Stage 1c leaves out "log level": `os.Logger` levels are controlled by the system, not the app. "Reveal logs" is an Open Console button.

### 1.10 Logging and diagnostics

`os.Logger` with subsystem `dev.mooring`, categories `engine`, `helper`, `guardrail`, `ipc`. Every lease create, renew, end and every helper call is logged with the lease id and reason. "Export diagnostics" bundles recent logs, `pmset -g` output, helper status and the lease table into a zip for bug reports.

### 1.11 Testing

- **Unit:** the reconciler as a pure function (leases + battery + thermal + lid → target state); `AutoOffPolicy` and `LidSessionTracker` tests ported from Awayke.
- **Integration:** a fake helper behind the same protocol; assert the watchdog restores sleep after the connection drops.
- **Manual release checklist:** lid closed on battery for 10 min with a `caffeinate`-free `ping` loop running; force-quit during lid mode and confirm `pmset -g | grep SleepDisabled` returns to 0 within 15 s; reboot during lid mode.

### 1.12 Level 1 acceptance criteria

- [ ] One icon toggles awake with a single click, no password, after one-time helper approval.
- [ ] Lid closed with no external display keeps a running process alive on AC and on battery.
- [ ] Force-killing the app restores normal lid sleep within 15 s.
- [ ] The menu lists every active lease with its reason and time left.
- [ ] Battery and thermal guardrails suspend lid mode and notify.
- [ ] The helper rejects XPC connections from any binary other than the signed app.

## Part 2: CLI, hooks and agent integration

Level 2 exposes the lease engine to scripts and agents, so the Mac stays awake exactly while Claude Code (or any agent) is working and returns to normal sleep when it stops. Every path below ends in the same lease table; none of them can talk to the root helper.

### 2.1 IPC between the CLI and the app

- **Transport:** a Unix domain socket at `~/Library/Application Support/Mooring/mooring.sock`, directory mode `0700`, socket `0600`. The app checks the peer with `getsockopt(LOCAL_PEERCRED)` and rejects any uid other than the logged-in user's.
- **Protocol:** newline-delimited JSON, one request and one response per line, with a `v` field for versioning. Example: `{"v":1,"id":"<uuid>","op":"acquire","args":{"kind":"lease","id":"claude-abc123","level":"system","ttl":900,"reason":"Claude Code: fix tests","watchPid":4121}}` (the full shape is under Engineering decisions → Socket protocol).
- **App not running:** the CLI starts it with `open -gj -b dev.mooring.app` and waits up to 3 s for the socket. If that fails it exits with code 3 and a one-line error; it never falls back to `pmset` or `caffeinate` itself.
- **Why a socket, not XPC:** the CLI is also invoked from hook scripts and other tools' sandboxes; a socket is simpler to call from any language, and privilege stays inside the app.

### 2.2 CLI reference

The binary ships at `Mooring.app/Contents/Helpers/mooring` and is signed with the app. It is not in `Contents/MacOS` because `MacOS/Mooring` and `mooring` are the same file on a case-insensitive volume. Settings offers "Install command-line tool", which symlinks it to `~/.local/bin/mooring` (creating the folder if needed, with no password). That is the only install path. A regular file already at `~/.local/bin/mooring` reads "Not a link (Mooring won't replace it)", and Reinstall is disabled. While the app runs from a place it won't stay (a Gatekeeper `AppTranslocation` copy, or a disk image under `/Volumes`), Install and Reinstall, the MCP **Add** and **Update** buttons (2.5) and Settings → Agents → Install are disabled with the caption "Move Mooring to Applications first", since each would write a path that later disappears. If `~/.local/bin` isn't on the shell's PATH, Settings shows the line to add to `~/.zshrc`, with a Copy button, and `mooring doctor` checks the real PATH. Homebrew installs the symlink automatically (stage 5).

| Command | Does |
| --- | --- |
| `mooring on [--level system\|display\|lid] [--for 2h] [--reason "…"]` | Turn on the menu's On switch: the same `menu` session a left click and the dropdown control. With no flags a live session is left alone and described (one that has just expired counts as off); otherwise one starts at Settings → "When I click the icon". With `--for` or `--level` the session is replaced, as picking a duration in the dropdown does: picked apps are cleared, the duration is `--for` or the click duration, and the level is `--level`, else the session's level, else the click level. `--reason` only appears in a lid approval's notification (the menu shows "Turned on from the menu bar") |
| `mooring off` | End the menu session (the `menu` lease and any picked apps), like a left click while on. Also ends a `cli` lease an earlier build left. Never touches agent leases or anchors. Idempotent: prints "Already off" and exits 0 when nothing was on |
| `mooring anchor [--level …] [--reason …] -- <command …>` | Lease tied to the child process; exits with the child's exit code |
| `mooring anchor --pid <pid> [--level …]` | Lease until that process exits |
| `mooring lease acquire <id> (--ttl 15m \| --watch-pid <pid>\|auto) [--level …] [--reason …] [--agent "<name>"]` | Named lease; needs `--ttl` or `--watch-pid`; re-acquiring a live lease's id renews it without weakening it (see Re-acquiring below) |
| `mooring lease renew <id> [--ttl …]` | Push the expiry forward; without `--ttl` it reuses the last TTL. Exits 1 if the lease doesn't exist |
| `mooring lease release <id> [--after 2m]` | End now, or shorten to a grace period (`--after` never lengthens). Idempotent: releasing a lease that is already gone exits 0 |
| `mooring status [--json]` | Effective level, all leases, battery, thermal, lid, helper state. `--json` fields: `summary` (the dropdown's first line), `effective {system, display, lid}`, `systemAssertion`, `displayAssertion`, `lidSleepDisabled`, `helperSleepDisabled`, `wantsLid`, `leases[]` (`id`, `owner {kind, name}`, `reason`, `level`, `expiresAt`, `watchPid`, `ttl`, `pendingApproval`), `power {onAC, batteryPercent}`, `thermal`, `lidClosed`, `helper`, `suspensions[]`, `notifications` (`allowed`, `alerts off`, `notDetermined` or `denied`), `agentLidApproval` (`askWhenOpenEnded`, `alwaysAsk`, `alwaysAllow` or `never`), `agentSessionLid` (whether Claude Code sessions ask for lid) |
| `mooring doctor [--json]` | One line per check: the app answers on the socket, `mooring` on PATH resolves to this app's binary, the helper is approved (a helper that was never registered passes as "not needed" when nothing wants lid and the Claude hooks can't ask for it), the helper's reading of lid sleep matches the engine's applied state (when it doesn't, the fix is "Turn lid mode off and on again"), `lidSleepDisabled` (read through the app and helper; the CLI never runs `pmset`), Mooring's Claude Code plugin is installed and enabled, Claude Code's major.minor version is the one the plugin was tested with (a different one only prints a note), notifications (check 7) and MCP clients (check 8, below). Eight checks in all. Exits 1 if any check fails |
| `mooring notify "<title>" ["<body>"]` | Post a macOS notification through the app, for when a long job finishes and the user may be away. Exits 0 when posted and 2 when denied or not shown (see Notify, below) |
| `mooring mcp` | Run the MCP server over stdio, for clients with no shell (2.5) |

**Conventions:**
- **Flags:** `--json` and `--no-launch` go after the subcommand (`mooring status --no-launch`), not before it. `--no-launch` skips starting the app (the hooks use it).
- **Durations:** `90s`, `15m`, `2h`, `1h30m`. A bare number, zero or an unknown unit is a usage error.
- **Exit codes:** 0 success; 1 usage error, `bad_request` or `not_found`; 2 request refused by policy, or held but paused by a guardrail (the reason is printed); 3 app unreachable; 4 `internal`.
- **Exit 3 messages:** all four print `mooring: <message>` on stderr (under `--json`, `{"ok":false,"error":{"code":"unreachable","message":"<message>"}}` on stdout):
  - not running: "Mooring isn't running and couldn't be started" (nothing listens on the socket, even after the launch attempt);
  - no answer: "Mooring didn't answer. It may be busy; the request may have gone through, so check `mooring status`." (connected, but the write failed, the reply timed out, ended early, was over 64 KiB or couldn't be read);
  - busy: "Mooring is running but didn't answer. Try again in a moment." (nothing was sent: the connect got `EAGAIN` because the app's queue of waiting connections was full, or the socket still wasn't answering when the launch wait ran out while a `dev.mooring.app` process was running);
  - blocked: "Can't reach Mooring's socket (permission denied). If this runs in a sandbox, allow ~/Library/Application Support/Mooring/mooring.sock" (never retried or launched).

  `anchor` treats all four as "the app isn't reachable" and doesn't start the command. `doctor`'s App check reads "not running", "didn't answer" (no answer or busy) or "permission denied", or "answered with an error: <message>" (fix: quit and reopen Mooring) when the app replied with an error.
- **Usage errors under `--json`:** when `--json` is among the arguments, every usage error (a parse or validation failure, or one found while running, such as "Couldn't find a process to watch") prints one line on stdout, `{"ok":false,"error":{"code":"usage","message":"<message>"}}`, nothing on stderr, and exits 1. `--help` and `--version` still print their text and exit 0. Without `--json`, the message goes to stderr as `mooring: <message>`.
- **Re-acquiring** a live named lease with `lease acquire` never weakens it (an expired one that the engine hasn't removed yet is replaced, not revived): the later expiry wins (the new length, or what the lease has left, whichever is longer, within the 4 h cap), the existing watch is kept unless `--watch-pid` is given, the level is the union of the old and new, the reason and owner are kept unless `--reason` or `--agent` is given. The rule that an agent's lease needs `--ttl` or `--watch-pid` reads the request's own, not the merged watch. `lease renew --ttl` is an explicit reset and is unchanged, and so are `on` and `anchor`.
- **Acquire output:** a lease or `anchor --pid` acquire that watches a process names it: `Lease job · while Claude Code (80) runs · 4h cap`, `Anchored anchor-80 · while Codex (80) runs`, or `while process 80 runs` when it can't be found. `status` and `--json` are unchanged.
- **Owner label:** "Terminal" by default for `anchor` and `lease` without an agent (`on` and `off` act on the menu session, labelled "Menu bar"). With `--watch-pid auto` it is the agent's name (`claude` → "Claude Code", `codex` → "Codex", otherwise the process name). `--agent "<name>"` overrides it.
- **Watching:** `--watch-pid auto` resolves the nearest ancestor process that isn't a shell, which for a hook or Claude's Bash tool is the Claude Code process.

**For agents** (also in `mooring --help`): two patterns, callable from any agent's shell.
- A whole job: `mooring lease acquire <name> --watch-pid auto --reason "…"` at the start and `mooring lease release <name>` when everything is finished. It also ends if the agent process exits, and has a 4 h cap you can extend with `lease renew`.
- One long command, including a script that outlives the agent's turn: `mooring anchor -- <command>`. It ends when the command exits and returns its exit code.

**Other ways in** map onto the same lease engine: MCP clients use `mooring mcp` (2.5), Raycast, Alfred and scripts use `mooring://` links (Links, below), and Shortcuts, Siri and Spotlight use App Intents (Shortcuts, below). Settings → Agents → Other agents (MCP) sets up MCP clients (below). Clipboard routes exist in none of them (Part 4).

### 2.3 Claude Code plugin

The plugin lives in `Integrations/claude-code-plugin/`. It has no `.mcp.json`: Claude Code reaches Mooring through its hooks and the `mooring` command (including `mooring notify`), not through MCP. It contains `.claude-plugin/plugin.json`, `hooks/hooks.json`, `scripts/mooring-hook`, `skills/mooring/SKILL.md` and `mooring.json` (`{"testedWithClaudeCode": "2.1"}`, the Claude Code major.minor it was tested with; `mooring doctor` reads it). Every hook command calls a small POSIX `sh` script, `${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook <Event>`, which finds `mooring` (`$MOORING_BIN`, `~/.local/bin/mooring`, `PATH`, the app's `Contents/Helpers/mooring`, then `/Applications/Mooring.app/...`) and runs `mooring hook <Event>`.

**Two ways to install it:**

- **From the app:** Settings → Awake → Agents → Install registers the bundled marketplace (`claude plugin marketplace add <Mooring.app>/Contents/Resources/ClaudePlugin`, or `marketplace update mooring-app` when it is already registered; if it is registered from a different path because the app moved, it is removed and added again) and then runs `claude plugin install mooring@mooring-app -y` (`claude plugin update …` when it is already installed), so the plugin's version always matches the app. After an update, Claude Code sessions need a restart.
- **From GitHub:** `/plugin marketplace add EidanErlich/mooring`, then `/plugin install mooring@mooring`. The repo's root `.claude-plugin/marketplace.json` publishes it.

**`mooring hook <event>`** (hidden from `--help`) reads up to 1 MiB of the hook's JSON from stdin and takes `session_id`, `cwd`, `notification_type`, `agent_id`, `agent_type`, whether any `background_tasks` entry is `running`, and the watched pid (resolved like `--watch-pid auto`: Claude's own process). It sends the wire op `hook` without launching the app and with a 1.5 s reply limit. It **always exits 0 and never prints to stdout** (Claude Code parses a hook's stdout); errors go to the `hook` log category. The prompt text is never read.

**Lease lifecycle for one session** (lease id `claude-<session_id>`, owner `.agent(name: "Claude Code")`, reason "Claude Code · <last path component of cwd>" (or "Claude Code · session <first 4 characters of the session id>" when there is no folder), level `system`, watching the Claude process). The events are the ones Claude Code 2.1.285 was recorded sending (`Packages/MooringIPC/Tests/MooringCLICoreTests/Fixtures/hooks/`), decided by `HookPolicy` in AwakeKit:

| Event | Action |
| --- | --- |
| Any event with an `agent_id` and an empty `agent_type` | **Ignored.** It's an internal helper agent, such as prompt suggestions after `Stop`. Counting it would keep the Mac awake for 15 min after every turn. |
| `UserPromptSubmit` | Acquire: watched, expiry 15 min. Re-acquire merging applies, so it never shortens an existing lease. |
| `PreToolUse`, `PostToolUse`, `PostToolBatch`, `SubagentStart`, `SubagentStop`, `PreCompact` | Renew: expiry = now + 15 min. If the lease is gone, acquire it as for `UserPromptSubmit`. |
| `PreToolUse` for a Bash command with a `tool_input.timeout` | Renew: expiry = now + max(15 min, timeout + 1 min), at most 4 h, because nothing fires until `PostToolUse`. If the lease is gone, acquire it with that expiry. MCP tool calls longer than 15 min aren't covered; wrap them in `mooring anchor`. |
| `PermissionRequest`, and `Notification` with `notification_type` `permission_prompt` | Expiry = now + the waiting timeout (Settings, default 30 min). Both fire for one prompt; the second is a no-op. |
| `Notification` of any other type (including `idle_prompt`) | **Ignored.** Claude sends the idle prompt after finishing a turn, while it waits for the next message. Counting it as waiting would keep the Mac awake for 30 min after every turn. |
| `Stop` or `StopFailure` (a turn that ended on an API error, such as a usage limit) with any `background_tasks` entry whose `status` is `running` | Renew, as for tool events. Claude is still working in the background. |
| `Stop` or `StopFailure` with no running background task | Release after 2 min, so the grace period covers background shells and quick follow-ups. |
| `SessionEnd` | Release now. |
| `SessionStart` or any unknown event | Ignored, so a future Claude Code version can't break anything. |

Renewals only ever extend: a renew sets the expiry to the later of its current value and its new one, so a short tool event never cuts a long Bash hold. Only the waiting timeout and the `Stop` grace set the expiry outright.

Pressing Esc to interrupt fires no `Stop`, so an interrupted turn keeps its lease for up to 15 min (up to the waiting timeout after Esc at a permission prompt) before the expiry ends it. If Claude Code crashes, the watched PID exits and the lease ends at once; if the PID can't be resolved, the 15-minute expiry is the backstop. Hook leases use the lid level while Settings → Awake → Agents → "Keep working with the lid closed" is on (the default), and the `system` level when it is off. Session leases always have an end, so they need no approval by default; under "Always ask" or "Never" see "Agent control and approvals" below. With "Keep awake while agents work" set to "Only when asked", every hook is acknowledged and does nothing.

**Hook rules** so Mooring can never break a Claude session:

- Every hook exits 0 with no output, even on errors; failures go to Mooring's log, not to Claude.
- `PreToolUse`, `PostToolUse`, `PostToolBatch`, `SubagentStart`, `SubagentStop` and `PreCompact` run with `"async": true` and `timeout: 5`. `UserPromptSubmit`, `Stop`, `StopFailure`, `Notification` and `PermissionRequest` are synchronous with `timeout: 2`; `SessionEnd` is synchronous with `timeout: 1`.
- Hooks never launch the app, and if `mooring` isn't installed the script is a no-op.
- Hook events and fields change over time; `mooring doctor` flags (without failing) its "Claude Code version" check when `claude --version` reports a different major.minor than the plugin was tested with.

Sketch of `hooks/hooks.json` (every event has the same shape; the real file lists all twelve):

```json
{
  "description": "Keep the Mac awake while Claude works",
  "hooks": {
    "UserPromptSubmit":  [{ "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook\" UserPromptSubmit", "timeout": 2 }] }],
    "Stop":              [{ "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook\" Stop", "timeout": 2 }] }],
    "Notification":      [{ "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook\" Notification", "timeout": 2 }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook\" PermissionRequest", "timeout": 2 }] }],
    "SessionEnd":        [{ "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook\" SessionEnd", "timeout": 1 }] }],
    "PreToolUse":        [{ "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook\" PreToolUse", "timeout": 5, "async": true }] }]
  }
}
```

(`PostToolUse`, `PostToolBatch`, `SubagentStart`, `SubagentStop` and `PreCompact` are the same as `PreToolUse`.)

**Skill** (`skills/mooring/SKILL.md`): tells Claude that the Mac stays awake automatically while it works and that it should never disable Mooring or change its settings. For jobs which outlive the turn (a background build, a long download) it should wrap them in `mooring anchor --reason "…" -- <cmd>`; for a long multi-step job it takes a named lease with `--watch-pid auto` and always releases it. It also says to call `mooring` directly (a wrapper such as `timeout`, `xargs` or `npx` would become the watched process), what to tell the user when the sandbox blocks the socket, and that exit code 2 means Mooring declined or paused the hold. It also says to prefer a lid-level hold (`mooring lease acquire job-<slug> --level lid --watch-pid auto`), which needs no approval, because `mooring on --level lid` with no end time asks the user first and may be declined. A last line says that when a long job finishes and the user may be away, `mooring notify "Done" "<what finished>"` tells them (rate-limited to one every 30 s).

### Agent control and approvals

Agents act automatically by default; Settings → Awake → Agents lets the user make each area explicit.

| Setting | Options | Default |
| --- | --- | --- |
| Keep awake while agents work | **Automatic** (hooks anchor every session) · Only when asked (hooks are no-ops; only `mooring anchor`, named leases or `keep_awake` calls count) | Automatic |
| When Claude is waiting for you, stay awake for | 10 · **30** · 60 min (how long a session blocked on a permission prompt keeps the Mac awake) | 30 min |
| Keep working with the lid closed | On · Off (Claude Code sessions use lid level while they work) | On |
| Lid mode for agents | **Ask only when it has no end** · Always ask · Always allow · Never | Ask only when it has no end |
| Let agents post notifications | On · Off (`mooring notify` and the MCP `notify` tool from agents; your own `mooring notify` is never affected) | On |
| Window arrangement by agents | **Automatic** · Ask first · Off | Automatic |

**Who counts as an agent.** The app decides from the caller's pid (`LOCAL_PEERPID`), walking the process ancestry (at most 64 steps, stopping at pid 1). A request is an agent request if any ancestor is named exactly (case included, after dropping a login shell's leading `-`) `claude`, `codex`, `cursor-agent`, `gemini`, `aider` or `opencode`, the agent CLIs (shown as "Claude Code", "Codex" and so on), and every `hook` request is one. Claude Code installed with npm runs as `node`, so a `node` whose script (its first argument after node's own `-` options, read with `KERN_PROCARGS2`) ends in `/claude` or lies in `/@anthropic-ai/claude-code/`, or whose argv[0] is exactly `claude` (Claude Code sets its process title to that, which overwrites the script in argv), counts as `claude`, here and for the owner label and the lid approval text. Anything else is a person: your Terminal, `launchd`, Raycast, scripts you start yourself, and the terminals inside the Claude and Codex desktop apps (`Claude`, `Codex`), which aren't the CLIs. Two kinds of caller are agents whatever their ancestry. **An MCP client** (a request carrying `client`, which only `mooring mcp` sends) is an agent named by `MCPClientName.display`, which closes the gap where an MCP server that Claude Desktop launches directly would count as a person. **A `mooring://` link** is an agent named after the app that sent it (see Links). Everything else the trade-off applies to: a process a desktop app launches directly, other than an MCP server, counts as a person. People are never asked. Shortcuts actions run as a person.

**For an MCP client** the agent's own process is the `mooring mcp` process that made the request, so a watch counts as an end only when it is on that process (or below it); a watch on an unrelated pid isn't an end.

**The decision.** An *open-ended* request has no expiry and no watched process of its own (for an agent, `mooring on --level lid` without `--for`). Session leases always have an end. A `lease` or `anchor` ends by its `--ttl`, or by its watch; for an agent, a watch counts as an end only when the watched pid is the agent's own process or runs below it (the watched pid's ancestry is walked, at most 64 steps). `--watch-pid auto`, `anchor -- <cmd>` (whose command runs under `mooring`, under the agent) and the hooks pass; an agent's `anchor --pid 1`, or a watch on its Terminal or its own parents, is open-ended, so it's asked under the default and refused under Never. `LidApproval.decide` (AwakeKit, pure) gives:

| Setting | Agent request with an end | Agent request with no end |
| --- | --- | --- |
| **Ask only when it has no end** (default) | allow | ask, unless the agent is always-allowed |
| Always ask | ask, unless the agent is always-allowed | ask, unless the agent is always-allowed |
| Always allow | allow | allow |
| Never | refuse | refuse (even for always-allowed agents) |

For `on`, an existing lid session counts as already approved only when it is itself open-ended; a bounded lid session doesn't let `on` become open-ended without asking. An agent's `on --until-off` (the wire's `untilOff`) without lid may replace a timed session with one that lasts until turned off: it asks for no lid, so it isn't an approval case (an agent may already start an open-ended session without lid, the pill shows ∞, and the guardrails still apply).

**Asking** posts a notification (category `mooring.lid-approval`): *"Claude Code wants to keep your Mac awake with the lid closed"*, with the body "Claude Code · <reason> · <with no end time | for 30m | while <process> runs>". For `on` the reason is the agent's `--reason`, else "mooring on". At launch the app withdraws approvals left from an earlier run, since their buttons would answer nothing. Its actions are **Allow once**, **Always allow this agent** (category actions are static, so the agent's name leads the body instead) and **Deny**; macOS shows them under the notification's **Options** menu. Mooring's notifications default to the Alerts style (`NSUserNotificationAlertStyle`), so a request stays on screen until it's answered. Clicking the body opens Settings and counts as no answer. "Always allow" appends the agent's name to `agentLidAlwaysAllowed`, listed and removable under Settings → Agents → Lid mode. Permission is requested the first time an approval is needed.

The call waits up to 60 s (the CLI allows 65 s for any request at lid level, including a plain `mooring on`). One ask runs per lease at a time. While it waits, `mooring status` shows "waiting for your approval", and so does the lease's row in the menu once the notification is posted (not while macOS is still asking for notification permission). On refusal, deny or timeout the lease is still created at the requested level without lid (unless it is a person's lid lease, below), and the reply is `denied` (exit 2) with one of:

- "Lid mode not approved (denied)";
- "Lid mode not approved (you denied it; ask again after 13:05)", for a request about the same lease within 15 minutes of a Deny (a Deny holds 15 minutes, or until the lease ends, so an agent can't nag but isn't shut out of a session that lasts until turned off);
- "Lid mode not approved (no answer in 60 s)";
- "Lid mode not approved (lid mode for agents is set to Never)";
- "Lid mode not approved (waiting for your answer to an earlier request)", for a second request while one ask is open;
- "Lid mode not approved (the request changed while you were deciding)", when an Allow arrives but the lease's lifetime or end changed (a watched lease is compared by its watched process, an unwatched one by "expiry no later");
- "Turn on notifications for Mooring in System Settings to approve lid mode", when notifications are denied or off, alerts are off or their style is None, or the system refuses the post (answered at once, without waiting).

A hook can't wait (Claude gives it 2 s), so under "Always ask" the session starts at system level, a notification is posted, and Allow upgrades the lease to lid. Battery guardrails apply after approval as always (1.7).

**Never and session lid off apply to live leases.** A refused or unapproved acquire ends without lid even when it re-acquires a lease that had it (re-acquiring merges levels, so lid is taken off afterwards), so the `denied` reply matches the outcome. That holds for leases an agent created, or whose lid an agent got. **A person's lid is theirs:** a live lease or menu session whose lid mode a person set (it isn't recorded as an agent's) is left untouched when an agent's lid request on it (`lease acquire`, `anchor` or `on`) is refused, and the reply is `denied` with the message above plus " Your lease is unchanged."; nothing changed, so the reply still matches the outcome. When an agent's `on` over such a session must be asked, the session stays as it is while the person decides, the ask describes it as it is, and Allow leaves it as it is (it has lid already, and the lid stays the person's). The hooks keep the rule above, since their `claude-…` leases are an agent's. While "Keep working with the lid closed" is off or the setting is Never, every hook event takes lid off the session's lease first. When the setting becomes Never, the app at once takes lid off every live lease that got it on an agent's behalf; when "Keep working with the lid closed" is switched off, off the `claude-…` session leases among them. The handler records which leases those are, so a person's own lid session is never touched. The record survives a relaunch: it is saved in the app's defaults (`agentLidGrants`, lease id → creation time) on every change, and at launch, after the leases are restored, only the entries that match a restored lease (same id, same creation time) are kept.

### Three ways an agent anchors the Mac

1. **Automatically:** the hooks above, no decision by the agent.
2. **Around a command:** the user says "run the full test suite, I'm closing my laptop", and Claude runs `mooring anchor --level lid --reason "full test suite" -- npm test`. The Mac stays awake until the command exits, then sleeps normally; the exit code passes through.
3. **Around something already running:** `mooring anchor --pid 4121 --level lid` holds the Mac awake until that process exits.

### 2.4 Other agents and tools

- **Any CLI agent** (Codex, Gemini CLI, Aider, Cursor's agent): `mooring anchor -- codex …` gives full coverage with zero integration. The README ships a one-line shell alias for each.
- **Agents that support hooks or notify commands:** the same `mooring-hook` script works if the tool can pass a session id; adapters live in `Integrations/<tool>/`.
- **`AGENTS.md` snippet:** two sentences agents can read telling them to wrap long jobs in `mooring anchor`.
- **CI and scripts:** `mooring anchor -- make release` for long local builds.

### 2.5 MCP server

`mooring mcp` is a stdio MCP server for agents without a shell (Claude Desktop, Cursor chat, any MCP client). It is hand-rolled inside MooringCLICore, with no new dependency, and relays each tool call to the app's socket.

**Transport and protocol**
- Newline-delimited JSON-RPC 2.0 on stdin and stdout, with logs on stderr. One reply per request, before the next line is read.
- It handles `initialize`, `notifications/initialized`, `ping`, `tools/list` and `tools/call`. Any other method gets error `-32601`, a malformed line `-32700`; notifications get no reply.
- `initialize` replies with the client's `protocolVersion` when it is `2025-06-18`, `2025-03-26` or `2024-11-05`, otherwise with `2025-06-18`. Capabilities are `{"tools": {}}`; `serverInfo` is `{"name": "mooring", "version": …}`. The server keeps `clientInfo.name`.
- Each tool call is one socket request, sent with `client` set to the name the client reported, or `""` before `initialize` names one (shown as "MCP client"), so every call is an MCP client's; and the app is launched if it isn't running, as the CLI does. Socket and wire errors become tool results with `isError: true` and the CLI's message text; protocol errors stay JSON-RPC errors. Bad arguments (an out-of-range `minutes`, an unknown `level`) are tool errors too, never a crash.
- The server exits on stdin EOF. Its leases watch its own pid, so they end when the client disconnects.

**Who the client is.** `client` makes the request an agent, whatever the process ancestry (see Agent control and approvals). The display name is `MCPClientName.display`: Claude Desktop's `claude-ai` becomes "Claude Desktop" and Cursor's `cursor-vscode` becomes "Cursor"; any other name is shown with control characters dropped, cut to 40 characters and trimmed, and "MCP client" when nothing is left. The name "Terminal" (in any case) also becomes "MCP client", so a client can't pass for a person. That name appears on the menu row, in approval notifications, in "Always allow" and in `notify`.

**Lease ids** are `mcp-<slug>-<server pid>-<n>`: the slug is the display name lowercased, non-alphanumerics turned into `-`, at most 24 characters ("client" when empty), and `n` counts from 1 within one server process. The pid keeps two servers of one client (two Claude Desktop windows) from sharing a lease. The app requires the pairing both ways: a request with `client` must use an `mcp-` id, and an `mcp-` id requires `client`. The owner is `.mcp(client:)`.

**Tools.** The tool list is fixed at build time; a test asserts exactly nine names (the four below and the five window tools in 3.4), and that no name or description mentions the clipboard.

| Tool | Arguments | Notes |
| --- | --- | --- |
| `keep_awake` | `minutes` (integer 1–240, required), `reason`, `level` (`system`, `display` or `lid`, default `system`), `lease_id` (optional, to extend one of this client's leases) | Creates `mcp-<slug>-<pid>-<n>`, or renews the named lease, with expiry = now + minutes and a watch on the `mooring mcp` process. It always has an end, so lid needs no prompt under the default setting; under "Always ask" the call waits for the answer (up to 60 s). A `lease_id` never shortens a lease. A new lease's reason is the `reason` given, else "Requested by <client>"; an extension keeps the lease's reason unless one is given (if the lease has expired, the new one again gets "Requested by <client>"). Every success has the same `structuredContent`: `{lease_id, level, ends_at, guardrail?}`, with `guardrail` only when the lease is held |
| `release_awake` | `lease_id` (optional) | Releases that lease, or every lease this server created when none is given. Another owner's lease gets "not one of this client's leases" |
| `awake_status` | none | Summary line, effective level, this client's leases, battery %, on AC, thermal state |
| `notify` | `title` (required, ≤ 80 characters), `body` (optional, ≤ 300) | Posts a macOS notification (see Notify, below) |

- **Under a guardrail,** `keep_awake` is still a success: the result carries `lease_id`, `level` and `ends_at` as usual, plus `guardrail` (for example "Lid mode waits for power"), because the app keeps the lease and applies it when the guardrail clears. The notice names `release_awake` as the way to end it.
- **"This client's leases"** means `owner == .mcp(client:)` with this client's display name **and** a watch on this server's pid. The server filters `status` itself and releases only the ids it created; the wire has no MCP-specific acquire or release kind. So two windows of one client can't release each other's leases.
- The MCP server never has clipboard tools; its window tools are `list_windows`, `arrange_windows`, `undo_arrangement`, `save_layout` and `apply_layout` (3.4). It exposes no way to end leases owned by the menu or by other agents.

### Notify

- **Wire:** the op `notify` with `NotifyArgs {title, body?, client?}`, result `NotifyResult {posted}`. The notification's title is "<Agent>: <title>", using the caller's agent name ("Claude Code", "Claude Desktop", …), or "Terminal" for a person; its body is the body; it has no category, so no buttons. An empty title is rejected with "Missing title".
- **Rate limit:** one per 30 s per agent name, and for MCP callers also one per 30 s per connection (the server's pid), because a client picks its own name. A faster call gets `denied` with "Rate-limited: try again in N s"; a last notification in the future (the clock moved back) counts as expired. People are never limited.
- **Setting:** Settings → Agents → "Let agents post notifications" (`AwakeSettings.agentNotifications`, default on). When off, agent callers get `denied` with "Notifications from agents are turned off in Settings"; it doesn't apply to people, so your own `mooring notify` always posts.
- **No permission:** `denied` with "Turn on notifications for Mooring in System Settings" (lid approvals keep their "…to approve lid mode" wording).
- **Not shown:** when the system refuses the notification, the reply is `posted: false`; the CLI prints "Mooring couldn't show the notification. Check System Settings → Notifications → Mooring." and exits 2, and the MCP `notify` tool returns it with `isError: true`.
- **CLI:** `mooring notify "<title>" ["<body>"]` exits 0 when posted and 2 when denied or not shown.

### Links (`mooring://`)

For Raycast, Alfred, bookmarks and scripts. Registered through `CFBundleURLTypes` with the scheme `mooring`. Links arrive through a `kAEGetURL` Apple-event handler that `AppDelegate` installs in `applicationWillFinishLaunching` (not `application(_:open:)`, since it needs the sender's pid), and a link that launches the app waits at the `HandlerGate` for the request handler; parsing is the pure `MooringLink.parse(URL) -> Result<LinkAction, LinkError>`. Every route acts on the menu session, the one switch behind `mooring on` and `off`:

| Link | Does |
| --- | --- |
| `mooring://on[?for=…&level=…&reason=…]` | `for` is `90s`, `15m`, `2h` or `1h30m`; `level` is `system`, `display`, `lid` or `display,lid`; a missing value takes `mooring on`'s default |
| `mooring://off` | Ends the menu session |
| `mooring://toggle[?…]` | Off if the menu session is on; otherwise on, with the same parameters as `on` |

- **The caller** is the app that sent the open request: the sender's pid comes from the `kAEGetURL` Apple event (`keySenderPIDAttr`), and the caller is that app's localized name ("Raycast"), or "A link" when there is no sender. It is always an agent for the lid rules, so `on?for=2h&level=lid` just works under the default; lid with no end posts "Raycast wants to keep your Mac awake with the lid closed"; and "Always allow" remembers "Raycast". The wait happens in the background: the link returns at once and the session starts without lid until you answer.
- **Errors** have no reply channel, so they post a notification titled "Mooring couldn't use that link", with one of "unknown action 'onn'", "'for' must look like 30m or 1h30m", "unknown level 'lidd'", or the refusal reason (for example "Lid mode not approved (lid mode for agents is set to Never)", where the rest of the request still applies, as in 2c-1). At most one error notification per 10 s.
- Links never open a window or bring Mooring to the front, and have no clipboard routes.

### Shortcuts (App Intents)

Three intents in `App/Intents/`, run in the background (`openAppWhenRun = false`), through the same request handler as `mooring on` and `off`. Shortcuts run as a person, trusted like the menu: they are never asked about lid mode.

| Intent | Parameters | Result |
| --- | --- | --- |
| **Keep Mac Awake** | Duration (optional), Level (optional: Normal, Keep display on, Keep awake with lid closed; empty keeps the running session's level, else the click level, like `mooring on` without `--level`) | Turns the menu session on. An empty Duration is open-ended (`untilOff`: until turned off, not the menu click's duration). Under a guardrail the dialog is the guardrail's notification title plus "Mooring is on and starts when that clears." |
| **Let Mac Sleep** | none | Ends the menu session |
| **Get Awake Status** | none | Returns an `AwakeStatus` entity: `isOn`, `summary`, `level`, `endsAt` (optional), `batteryPercent`, `onPower`. The dialog shows the summary |

An action that runs before the app has set itself up (a Shortcut that launches Mooring) waits for the handler: `IntentActions` owns the `HandlerGate` the app hands its handler to. The `AppShortcutsProvider` phrases are "Keep my Mac awake with Mooring", "Let my Mac sleep with Mooring" and "Is my Mac staying awake with Mooring". Clipboard intents and intents for named leases are excluded.

### Settings → Agents → Other agents (MCP)

A section under Lid mode, built on `MCPClientConfig` (MooringIPC, shared with `doctor`), a pure struct over a file URL with an injected file system, so tests run on temporary directories.

| State | Meaning | Button |
| --- | --- | --- |
| **Not installed** | The client's config folder doesn't exist | none |
| **Not added** | The client is installed but has no `mooring` entry | **Add** |
| **Added** | `mcpServers.mooring` runs this app's helper (`Contents/Helpers/mooring`) with `["mcp"]` | **Remove** |
| **Needs update** | The entry points somewhere else | **Update** |

- **Config files:** Claude Desktop `~/Library/Application Support/Claude/claude_desktop_config.json`; Cursor `~/.cursor/mcp.json`. A missing file counts as `{}` when the folder exists.
- **Add** and **Update** (the same operation): read the file; if it isn't a JSON object, or `mcpServers` isn't an object, change nothing and show "<file> isn't valid JSON, so Mooring left it alone. Use Copy config instead."; copy the original to `<file>.mooring-backup` (overwriting an earlier backup, keeping its permissions); set `mcpServers.mooring = {"command": "<app>/Contents/Helpers/mooring", "args": ["mcp"]}` and keep every other key; write atomically with sorted keys (so key order may change, which the caption says); show "Restart <client> to load it." A symlinked file is written through and stays a link; a dangling one is followed to where it points (relative to the link's folder), creating that file's folder if needed.
- **Remove** deletes `mcpServers.mooring` only, with the same backup, and drops an empty `mcpServers`.
- **Copy config** puts `{"mcpServers": {"mooring": {"command": "…", "args": ["mcp"]}}}` on the clipboard (Mooring's own snippet, not clipboard history), with the caption "Paste into your MCP client's config. Most clients call this file mcp.json." The section's other caption is "Mooring rewrites the file with sorted keys and keeps a .mooring-backup next to it."
- The rows refresh when the section appears and after each action. **"Let agents post notifications"** sits in this section.
- **`doctor` check 8, "MCP clients",** reads the same files with the same code (the app isn't involved): ✓ lists the clients that are Added ("Claude Desktop, Cursor"); – "none added"; ✗ "Claude Desktop needs update" when an entry runs another path, with the fix "Settings → Agents → Update".

### 2.6 Policy for non-menu callers

| Rule | Trusted ops (`on`, `off`, `anchor`) | Named leases (`lease acquire`, `renew`, `release`) |
| --- | --- | --- |
| Until turned off | Allowed, like the menu | Not allowed: `--ttl` or `--watch-pid` is required |
| Max length | Engine max (12 h) | 4 h, including a watched lease with no TTL; renewable while renewals keep arriving |
| `lid` level | Allowed (guardrails apply), like the menu | Allowed for people; for agents `LidApproval` decides (named leases with a TTL, or watching the agent's own processes, have an end, so they are allowed by default; see Agent control and approvals) |
| Ids | `menu` (`on`, `off`), `anchor-<pid>` | 1 to 64 characters of `[A-Za-z0-9._-]`; reserved ids (`menu`, `lid-session`, `app-*`, `cli`, `anchor-*`) are refused; `mcp-*` ids belong to MCP clients (a request with `client` needs an `mcp-` id and an `mcp-` id needs `client`) |
| Max concurrent leases | 32 live leases; a socket request past that gets exit code 2 (the menu is never refused) | Same |
| Reason text | Trimmed to 80 characters, control characters stripped before display | Same |
| Guardrails (1.7) | Always win; the caller is told in the response | Same |

Any process running as the user can take a lease; that's the same trust level as running `caffeinate`, and the menu always shows who holds one. Agent detection is advisory: an agent can escape it by detaching itself (a process reparented to `launchd` has no agent ancestor) or by launching `mooring` through other apps (Terminal, `osascript`), so it guards against accidents, not against a hostile agent.

### 2.7 Notifications for walk-away use

Optional notifications when an agent lease ends ("Claude Code finished · 42 min") and when a guardrail suspends lid mode. With iPhone Mirroring or Focus sync these reach the phone; direct push (ntfy or Pushover URL) is a later add-on, off by default.

### 2.8 Level 2 acceptance criteria

- [ ] With the plugin installed, closing the lid mid-task keeps Claude working, and the Mac sleeps within 2 min of Claude stopping.
- [ ] Killing the Claude Code process ends its lease immediately.
- [ ] A Claude session waiting on a permission prompt lets the Mac sleep after 30 min.
- [ ] `mooring anchor -- sleep 60` keeps the Mac awake for 60 s and exits 0.
- [ ] Hooks add under 50 ms to a prompt submit and never surface an error in Claude Code.
- [ ] `mooring doctor` diagnoses a missing helper approval, a missing CLI and a missing plugin.
- [ ] Claude Desktop, after Add and a restart, can keep the Mac awake and post a notification through `mooring mcp`; its leases end when it quits.
- [ ] `mooring://on?for=1h&level=lid` from Raycast starts lid mode with no prompt, and an open-ended lid link asks "Raycast wants…".
- [ ] The Shortcuts actions turn the menu session on and off and report its status.

## Part 3: Window management (from Loop)

**Status:** stage 3a (WindowKit, version 0.0.4) and stage 3b (agent windows, version 0.0.5) are built. Loop's window manager runs inside Mooring, off by default, with the Windows submenu, the Windows settings group, the Accessibility flow and the Shortcuts page; agents arrange windows with `mooring win` and the MCP window tools (3.4, as built).

Level 3 vendors Loop's window engine into a `WindowKit` package and runs it inside Mooring, off by default, behind the same menu-bar icon. It is the largest import (about 180 Swift files) and the only one that uses private macOS APIs, so it is isolated as a module that can be switched off entirely.

### 3.1 Features carried over

| Feature | From Loop | In Mooring v1 of level 3 |
| --- | --- | --- |
| Radial menu | Hold trigger key, move the pointer toward a direction | Yes, with Loop's theming (width, shape, colour) |
| Preview window | Shows the target frame before committing | Yes |
| Keyboard actions | Trigger key + key for about 50 actions: halves, quarters, thirds, maximize, almost maximize, centre, grow/shrink, move, next/previous screen, undo, initial frame | Yes, with Loop's defaults |
| Cycles | Repeat a keybind to step through a sequence of actions | Yes |
| Custom frames | User-defined positions and sizes | Yes |
| Snap by drag | Drag a window to an edge | Yes |
| Stash | Hide windows at a screen edge, reveal on hover | Later (depends most on SkyLight private APIs) |
| Focus switching | Move focus between windows by direction | Later |
| `loop://` URL scheme | Scripting | Replaced by `mooring win` (3.4, built in 3b) |

**Mooring-only addition, later:** saved layouts ("Coding: terminal left two-thirds, browser right third"), which Loop's own comparison table lists as missing. A layout is a named list of (app bundle id, screen, action or frame). Stage 3b built `mooring win layout save | apply | list | delete <name>` and the MCP `save_layout` and `apply_layout`; a hotkey for layouts is not built.

### 3.2 What gets removed from Loop

- Its own menu-bar icon, dock tile (`LoopDockTile`), About window and onboarding. Mooring's dropdown gains a Windows section instead.
- Its updater (`LoopUpdaterHelper`, ZIPFoundation). Mooring has one updater for the whole app (Appendix).
- Settings migration code for old Loop versions.
- Loop's settings window, rebuilt as the Windows settings group inside Mooring's settings. Loop's `Luminare` UI package is kept for those pages, since 36 Loop files import it (owner decision, 2026-10-03: Keep Luminare). Loop's Launch at login, Start hidden and Hide menu bar icon controls are removed from the Behavior page, because Mooring has its own.

Dependencies kept: `Defaults` (shared with Maccy and level 1), `Scribe` (logging; replaced with Mooring's `os.Logger` if the port is small).

### 3.3 Permissions

Window management needs **Accessibility** (`AXIsProcessTrusted`). Mooring requests it only when the user turns on Windows, never at first launch: Turn On asks macOS once to list Mooring under Accessibility (`AXIsProcessTrustedWithOptions` with the prompt option), then shows a sheet explaining why, with a hint to add Mooring with + if it isn't listed, and a button to open **Privacy & Security → Accessibility**. Levels 1 and 2 never need it. If permission is later revoked, Windows switches itself off and the icon shows the orange attention pill (stage 3a adds the reason "Windows needs Accessibility"; `windowsEnabled` stays true, and Windows resumes by itself when trust returns; **Turn Off Windows** in the submenu, or the Window Manager toggle, turns it off and clears the pill). Mooring checks for revocation every 5 s while Windows is on. After **Turn On…** it polls for trust every 2 s for up to 5 minutes, so granting Accessibility needs no relaunch.

Maccy's paste action (level 4) needs the same permission, so granting it once covers both.

### 3.4 CLI and agent window control

*As built in stage 3b.* An agent arranges windows from a plain request ("Chrome on the right half, iTerm bottom left, Slack top left") by reading the current windows, sending one plan, and reporting what landed. Mooring holds the Accessibility permission and does the matching and moving; the agent never needs Accessibility itself.

**Where the work happens.** In the app, through four socket ops: `win.list` and `win.undo` (each with an optional `client`), `win.arrange` and `win.layout`. The CLI and the MCP server only relay them. `WindowSystem` (a protocol in WindowKit, with a live implementation over Loop's `Window` and the Accessibility API) and the `Arranger` (in the app, pure over `WindowSystem`) do the matching, resolving, applying, undo and layouts; `RequestHandler+Windows.swift` gates every request.

**The flow for one request:**

1. **Look.** `mooring win list --json` returns running apps and their windows (id, title, frame, screen, minimized, full screen) and every screen (id, name, visible frame, position). Accessory apps (menu-bar-only apps with no Dock presence) are not listed, so they can't be arranged.
2. **Plan.** The agent maps the request to one plan, all placements at once. A plan has at most 32 placements, and a `frame` is clamped to 0–1.
3. **Execute.** Mooring resolves every placement first, then applies the moves in one pass, optionally flashing Loop's preview overlay (0.6 s) before moving. One arrangement applies at a time.
4. **Report.** Mooring returns a status per placement; the agent tells the user anything that didn't land and can ask about ambiguous windows.

**CLI:**

| Command | Does |
| --- | --- |
| `mooring win list [--json]` | Apps, windows and screens as above |
| `mooring win arrange <app>=<region>[@screen] … [--launch] [--preview] [--json]` | One transaction, e.g. `mooring win arrange chrome=right-half iterm=bottom-left slack=top-left` |
| `mooring win arrange --plan <file or ->` | Same, with the full JSON plan |
| `mooring win do <action> [--app <name>] [--screen …]` | One Loop action on one window. With no `--app` it targets the frontmost app (`@frontmost`). SPEC's earlier `mooring win <action>` would collide with the subcommand names, so `do` replaces it |
| `mooring win undo` | Put every window moved by the last arrangement back |
| `mooring win layout save \| apply \| list \| delete <name>` | Saved layouts ("save this as coding") |
| `mooring win list-regions` | Every region name the planner accepts |

`win do` travels as a one-placement plan whose `app` is the sentinel `@frontmost`; the app resolves it to the frontmost regular app other than Mooring. Human output for `arrange` is one line per placement, such as `iterm ok (was minimized, restored)`, `notes isn't running` or `code ambiguous: matches several apps: Visual Studio Code, Xcode`; `--json` prints the result.

**Exit codes.** 0 when every placement is `ok`; 2 when any placement isn't (`partial`, `ambiguous`, `not_running`, `not_found`, `failed`), and when the request is `denied`; 1 for a bad plan, and for "Nothing to undo"; 3 when the app is unreachable. Mutating requests (`arrange`, `do`, `undo`, `layout save | apply | delete`) use a 120 s client timeout (an ask's 60 s, the lock wait and a 10 s launch), and so do `list` and `list-regions`, since a list can wait 1.5 s on each hung app; `layout list` uses the normal one.

**Plan schema:**

```json
{
  "placements": [
    { "app": "chrome", "region": "right-half" },
    { "app": "iterm",  "region": "bottom-left", "screen": "main" },
    { "app": "slack",  "region": "top-left" },
    { "app": "vscode", "title": "mooring", "frame": { "x": 0, "y": 0, "w": 0.6, "h": 1 } }
  ],
  "launch": false,
  "preview": false
}
```

- **`app`** is matched case-insensitively against running apps' names and bundle ids, in three tiers: an exact name or bundle id wins; otherwise a prefix match; otherwise a substring match ("iterm" → iTerm2 `com.googlecode.iterm2`, "vscode" → Visual Studio Code `com.microsoft.VSCode`). The bundle id's last component counts as well, so "code" matches both Visual Studio Code and Xcode and is `ambiguous` when both run. Ties within a tier are `ambiguous`, never guessed.
- **`region`** is a Loop action name in kebab case (`left-half`, `right-half`, `top-left`, `bottom-left`, thirds, two-thirds, `maximize`, `almost-maximize`, `center`, …); `mooring win list-regions` prints them all. Only actions that set a window's position and size are regions, so `win undo` can always put them back: halves, quarters, thirds and two-thirds, fourths and three-fourths, `maximize`, `almost-maximize`, `maximize-height`, `maximize-width`, `fill-available-space`, `center`, `mac-os-center`, `larger`, `smaller`, `scale-up`, `scale-down`, the shrink, grow and move steps, and `next-screen`, `previous-screen`, `left-screen`, `right-screen`, `top-screen`, `bottom-screen`. The Windows menu's other actions (`minimize`, `minimize-others`, `hide`, `fullscreen`, which is macOS full screen, Space moves, Loop's `undo` and `initial-frame`, focus, stash and cycles) are `failed` with "region isn't available to agents". An unknown region is reported on that placement. **`frame`** gives fractions of the screen's visible area for anything else, origin top-left.
- **`screen`** is `main`, `left`, `right`, or an index; default is the screen the window is on. `left` and `right` are relative to the main screen.
- **`title`** picks one window, case-insensitively: a window titled exactly that wins; otherwise one whose title contains it. Several at the tier that decides is `ambiguous`, so "GitHub" picks the window titled "GitHub" over "GitHub - Pull requests". With no `title`, the app's frontmost window is used, even when the app has several.
- Minimized windows are restored. A full-screen window is `failed` ("is full screen"). Apps that aren't running are launched only when `launch` is true, waiting up to 10 s for a window.

**Result per placement** (`WinPlacementResult`, in a `WinArrangeResult`): `ok` (with the final frame), `partial` (the app enforces a minimum size; final frame given; it compares size only), `ambiguous` (`candidates` listed, and a `reason` of "matches several apps: …" or "matches several windows: …", so the agent knows whether to refine `app` or `title`), `not_running` ("isn't running", or why it couldn't be opened), `not_found`, or `failed` (reason).

**Undo** keeps the last 10 arrangements in memory (window id → previous frame); `win undo` reverts the latest. It is lost on quit. With nothing to undo the reply is `notFound`, "Nothing to undo". When none of the arrangement's windows can be found but an app of theirs still runs (Accessibility lists no windows on another Space), each window whose app runs is `not_found` with "couldn't find the window — it may be on another Space; switch to it and try again" (one whose app quit is "the window is gone") and the arrangement is kept for the next `win undo`; otherwise a missing window is "the window is gone" and the arrangement is dropped.

**Saved layouts** live in `~/Library/Application Support/Mooring/layouts.json` (name → placements of bundle id, screen, and region or frame as screen fractions). A file that won't decode is renamed to `layouts.corrupt-<unix time>.json` beside it (with `-1`, `-2`, … if taken), logged once and treated as empty, so it never blocks saving or listing. `save` captures the frontmost window of each visible app on each screen; `apply` checks the stored placements as any plan (`WinPlan.validated()`: at most 32, frames clamped; otherwise `bad_request` "Layout <name> is invalid: …") before asking, then runs them with `launch: true`.

**Accessibility timeouts.** `WindowKit.start()` sets a 1.5 s messaging timeout on the system-wide Accessibility element, which makes it the default for every element in the process, so every Accessibility call (Loop's own, on elements it creates, included) gives up after 1.5 s. `LiveWindowSystem` also sets it on each application and window element it reads. One hung app can't stall a request for long.

**MCP tools** (same schema as the CLI; every call carries the client's name, so it counts as an agent, and goes through the 120 s client): `list_windows`, `arrange_windows(placements, launch, preview)`, `undo_arrangement`, `save_layout(name)`, `apply_layout(name)`. Results are text plus `structuredContent` with the per-placement results. With these the server has 9 tools (2.5).

**Skill guidance:** list windows before arranging; send one plan rather than one call per window; report every placement that isn't `ok`; offer `mooring win undo` if the user doesn't like the result. The skill's description and title mention window arrangement so that it loads for these requests.

**Gating.** Settings → Agents → "Window arrangement by agents" (`AwakeSettings.agentWindows`): **Automatic** (default) · Ask first · Off, with the caption "Agents can move and resize your windows with `mooring win` and MCP. Windows must be on."

- **Windows off** (the `WindowsController` state isn't on): every `win` op, `list` included, is `denied` with "Windows is off. Turn it on in Mooring (Windows › Turn On…)." It never turns Windows on by itself.
- **Off** (agents): every agent `win` op is `denied` with "Window arrangement by agents is off in Settings": `win.arrange`, `win.undo`, every `win.layout` action, and `win.list` too (so `list-regions` and the MCP `list_windows`), since window titles reach an agent only through Mooring's Accessibility. People are unaffected.
- **Ask first** applies to `win.arrange` (including `win do`) and `win.layout apply`; undo, layout save and delete never ask. It posts a notification (category `mooring.window-approval`) "<Agent> wants to arrange N windows" with the actions **Allow** and **Deny**, and a body that lists at most 6 placements and then "and N more". The agent's app names and titles are shown without control or formatting characters and cut to 40 characters, and a layout's saved bundle ids are shown as the apps' names (the id itself when no installed app has it); a plan with `launch` and every layout apply end with the line "May open apps that aren't running." It waits 60 s; Deny, no answer or unavailable notifications (including alerts off and a refused post, answered at once) are `denied`, and the last says "Turn on notifications for Mooring in System Settings to approve window arrangement". The mode and the Windows state are checked again right before applying, so a change made while the ask was open takes effect. A layout apply applies exactly the placements that were approved.
- **People are never asked.** The caller is an agent by the same detection as in Agent control and approvals (process ancestry, an MCP `client`, a link).

Example exchange:

```
You:    Put Chrome on the right half, iTerm bottom left and Slack top left.
Claude: mooring win list --json
        mooring win arrange chrome=right-half iterm=bottom-left slack=top-left --json
        → chrome ok
          iterm ok (was minimized, restored)
          slack ok
Claude: Done. iTerm was minimized, so I restored it. Say "undo" to put them back.
```

### 3.5 Shortcuts and conflicts

A single **Shortcuts** page (General › Shortcuts) lists every global hotkey across all levels: the awake toggle, Loop's trigger key and keybinds, the clipboard popup. It flags conflicts with each other and with system shortcuts it can detect. Loop's default trigger key is kept. Its README suggests remapping Caps Lock to Control, which the tab links to rather than doing itself.

### 3.6 Risks specific to Loop

- **Private APIs.** Loop binds SkyLight symbols (`@_silgen_name`, runtime symbol loading) for stash, window tags and some moves. These can break on any macOS update. Mitigation: every private-API path sits behind a capability check, fails closed (the feature hides itself) and is logged; the release checklist tests each macOS beta.
- **License.** Loop is GPL-3.0, which is why the monorepo is GPL-3.0-only (Overview).
- **Contribution norms.** Loop's `AI_POLICY.md` requires disclosure and human verification for AI-assisted contributions *to Loop*. It doesn't restrict forking, but fixes sent back upstream must follow it.
- **Keeping up with upstream.** Loop is actively developed (last commit 2026-09-29). It is vendored as a plain snapshot (Build brief); later upstream fixes are ported by hand and logged in `THIRD_PARTY/Loop/UPSTREAM.md`.

### 3.7 Level 3 acceptance criteria

- [ ] With Windows off, Mooring never asks for Accessibility and loads none of `WindowKit`.
- [ ] Radial menu, preview, keyboard actions and cycles behave as in the upstream Loop commit that was vendored.
- [ ] The Chrome / iTerm / Slack request lands in one `mooring win arrange` call, and `mooring win undo` restores the previous layout (built and covered by `Arranger`, handler, CLI and MCP tests over a fake `WindowSystem`; needs the owner check with Accessibility)
- [ ] A failing private-API call hides the dependent feature instead of crashing.
- [ ] The Shortcuts page detects a clash between the Windows trigger and the clipboard hotkey.

## Part 4: Clipboard history (from Maccy, never exposed to agents)

**Status:** stage 4 (ClipKit, version 0.0.6) is built and reviewed. Maccy@c376789 runs inside Mooring, off by default, with the Clipboard submenu and popup, Settings → Clipboard, the Shortcuts row and the agent wall (4.3, as built). The final review's fixes are in: the App Intents wall covers the whole app (4.3), turning Clipboard off honours "Clear history on quit" and Settings can delete saved history (4.4), and the edges in 4.8. Two criteria in 4.7 are left for the owner check.

Level 4 vendors Maccy as a `ClipKit` package, off by default, with the same storage and privacy behaviour as Maccy (no added encryption, decided 2026-09-29). Agents get no clipboard API: no CLI command, MCP tool, App Intent, URL route or AppleScript returns history.

### 4.1 Features carried over

| Feature | Maccy behaviour kept |
| --- | --- |
| Popup | ⇧⌘C (configurable) opens the Clipboard popup (Maccy's panel, adapted as `ClipboardPanel`) with search focused. Its header reads "Clipboard" |
| Search | Type to filter; exact, fuzzy and regex modes with match highlighting |
| Copy / paste | Return copies; ⌥Return pastes; ⌥⇧Return pastes without formatting; ⌘/⌥ + number for the first items |
| Pins | ⌥P pins an item to the top with a permanent shortcut |
| Content types | Text, rich text, images, files, colours, with the source app's icon |
| Delete and clear | ⌥⌫ deletes one; "Clear" removes unpinned; Clear with ⌥ ("Clear All") removes all. Both ask first, as Maccy does, unless "don't ask again" is set |
| Pause | "Pause Recording" (a checked toggle) and "Ignore Next Copy" as items in the Clipboard submenu (Maccy uses ⌥-click on its own icon for these) |
| History size | Default 200 items, adjustable |

### 4.2 What gets removed from Maccy

- **App Intents** (all six files in `Intents/`, including `Get.swift`, `Select.swift`, `Delete.swift`, `Clear.swift`). "Get" and "Select" would let Shortcuts, and anything that can run `shortcuts run`, read the history. All are deleted, not hidden.
- Its menu-bar icon, updater (Sparkle moves up to the app level), App Store review prompt and About window.
- The `defaults write … ignoreEvents` switch, replaced by the Pause menu item.
- Maccy's `Settings/`, rebuilt as Settings → Clipboard (4.8). Its `Notifier` is a no-op, so nothing about a copy reaches a notification.
- In the popup, **Quit** is gone and **Preferences** (⌘,) opens Settings → Clipboard → History; there is no About.
- Left out of the vendored snapshot because nothing uses them: `GlobalHotKey.swift` (it calls `Shortcut` methods no KeyboardShortcuts release has, so it can't compile) and both `.xcdatamodeld` files. `FloatingPanel` is replaced by a `PopupPanel` protocol in ClipKit plus the app's `ClipboardPanel` (`App/UI/`).

Maccy's SwiftData models (`HistoryItem`, `HistoryItemContent`) are kept; that's why the whole app needs macOS 14.

### 4.3 The agent wall

| Path an agent could use | How it's closed |
| --- | --- |
| `mooring` CLI and socket | No clipboard operations exist in the IPC protocol; unknown ops are rejected |
| MCP server | No clipboard tools; the server's tool list is fixed at build time |
| Shortcuts / App Intents | Maccy's intents deleted (4.2); only `App/Intents/` may declare an intent, and none names the clipboard |
| URL scheme | `mooring://` has no clipboard routes |
| AppleScript | No scripting dictionary, and `NSAppleScriptEnabled` is `false` in `App/Info.plist` |
| Reading the database file | File permissions only; see the known limitation in 4.4 |
| Reading the live pasteboard | Out of Mooring's control; any app can read the *current* clipboard, as today |

The last row is worth saying plainly in the README: Mooring protects the history, not whatever you most recently copied.

**As built, the wall is tests, not convention.** `AgentWallTests` (11 tests, in `App/Tests/`) and `noClipboardMCPTools` (in `Packages/MooringIPC/Tests/MooringCLICoreTests/AgentWallMCPTests.swift`, because the MCP tool table is internal to that target) fail the build when:
- a file under `App/IPC/`, `App/Links/`, `App/Intents/` or `Packages/MooringIPC/Sources/` mentions `ClipKit`, `HistoryItem`, `Clipboard.shared`, `Storage.shared`, `ClipboardController` or `NSPasteboard`, or names a clipboard, pasteboard or history concept at all (case-insensitive), so a neutrally named closure can't smuggle one in; each folder must exist and contain Swift files, so the scan can't pass vacuously;
- `Packages/MooringIPC/Package.swift` mentions ClipKit;
- every subfolder of `App/` isn't classified as an agent path or not (a new folder fails until someone decides), or the `RequestHandler(` arguments in `AppDelegate.swift` mention the clipboard;
- an `Op` (`Op` is `CaseIterable`), an MCP tool or a `mooring://` route matches clipboard, paste or history;
- ClipKit declares an `AppIntent`, `AppEntity` or `AppShortcutsProvider`;
- any file under `App/` outside `App/Intents/` and `App/Tests/` imports `AppIntents` or names `AppIntent`, `AppEntity`, `TransientAppEntity`, `AppShortcutsProvider`, `EntityQuery`, `EntityStringQuery` or `EnumerableEntityQuery` (App Intents are extracted from the whole app target, so an intent beside `ClipboardController` would otherwise reach Shortcuts); `App/Intents/` itself gets the clipboard name scans above;
- the built app's `Metadata.appintents` (what Shortcuts reads) matches clip, paste or history, case-insensitive (skipped if the test host has none);
- `NSAppleScriptEnabled` isn't `false`, or an `.sdef` file exists under `App/` or in the bundle.

Known gaps are in `docs/BACKLOG.md`: the scan reads Swift source text, not linked symbols, and its parenthesis matcher ignores parentheses inside strings and comments.

### 4.4 Storage

- The store is its own SwiftData container, `~/Library/Application Support/Mooring/Clipboard/Storage.sqlite`, separate from settings and leases, directory mode `0700`. Contents are stored as Maccy stores them, unencrypted.
- The store is excluded from Time Machine and iCloud backups (`isExcludedFromBackup`).
- The folder and store are created only when Clipboard starts. If the folder can't be created, set to `0700` and excluded from backup, ClipKit falls back to an in-memory store, so nothing is written unprotected; the store keeps the location it first opened at for the rest of the process. If the store itself won't open, it also falls back to memory. Both logs carry only the error's code (and, for the store, its type), never a path.
- Maccy's settings live in the `dev.mooring.clipboard` `UserDefaults` suite (`dev.mooring.clipboard.tests` under a test host), never in Mooring's own defaults, except the popup hotkey: KeyboardShortcuts keeps it as `KeyboardShortcuts_clipboardPopup` in the standard defaults, as it does every shortcut.
- Retention matches Maccy: keep the last 200 items by default. "Clear history on quit" is an optional setting; it also applies when Clipboard is turned off while running, so the session's unpinned items aren't left on disk.
- Turning Clipboard off stops recording but keeps what's saved. While it's off and the folder exists, Settings → Clipboard → History offers **Delete Clipboard History…**, which asks "Delete all saved clipboard history?" ("This can't be undone.", Delete / Cancel) and removes the whole `Clipboard/` folder, pins included, without starting ClipKit (it drops history loaded earlier in the session too).

**Known limitation.** Maccy runs sandboxed, so macOS guards its history file with an "access data from other apps" prompt. Mooring ships unsandboxed, like Loop and Awayke, so any process running as you, including an agent with shell access, can read the history file without a prompt. Closing that gap would take either encryption or moving ClipKit into a separate sandboxed helper app; revisit if it matters.

### 4.5 What's never recorded

- Pasteboard types marked confidential or temporary: `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType` (always, as in Maccy).
- Maccy's default ignored pasteboard *types* (not apps): the private types 1Password, KeeWeb, TypeIt4Me and similar tools put on their copies, editable in Settings → Clipboard → Ignore Rules → Ignored types. The default ignored *apps* are listed below.
- Copies made while Secure Keyboard Entry is active (`IsSecureEventInputEnabled()`), which covers most password fields. This is new code, not in Maccy.
- Copies from apps on the ignore list. The defaults are 1Password 7 and 8, Bitwarden, Dashlane, LastPass, KeePassXC, Keychain Access and Passwords; the list is editable in Settings → Clipboard → Ignore Rules.
- Universal Clipboard copies from other devices (`com.apple.is-remote-clipboard`), unless the user turns them on (off by default).
- Copies with more than 1,000 items or contents. They aren't recorded at all: SwiftData's insert cost grows with the square of the content count (a 10,000-file Finder copy froze the main thread for about 12 s).
- Nothing recorded reaches a log or a notification. ClipKit logs ids and counts only, and its tests use a private pasteboard and prove the real one is untouched.

### 4.6 Permissions

Recording history needs no permission. Auto-paste needs **Accessibility**, the same grant level 3 uses. Without it, selecting an item copies it and the user pastes with ⌘V; the popup's footer then reads "Paste with ⌘V. Allow Accessibility in Windows to paste automatically." The hint is read again whenever the popup becomes key, so it goes once Accessibility is granted. Clipboard never prompts for Accessibility itself: that prompt belongs to Windows' Turn On.

### 4.7 Level 4 acceptance criteria

- [x] With Clipboard off, nothing is recorded and no store is created (`offMeansNoStoreNoPolling`; a released or stopped kit stops, and `popupView()` is empty while off).
- [ ] A password copied from 1Password never appears in history. The ignore list, concealed types and the Secure Keyboard Entry check are covered by tests with an injected frontmost app; a copy from the real 1Password needs the owner check.
- [x] No CLI command, MCP tool, App Intent, URL or AppleScript call returns history contents (`AgentWallTests` and `AgentWallMCPTests`, 4.3).
- [ ] Popup opens in under 100 ms with 200 items, and search filters as you type. A test builds the item list from 200 fixtures within budget, and search is Maccy's own tested code; the live popup timing needs the owner check.
- [x] The Shortcuts page detects a clash between the clipboard hotkey and a Windows keybind (`clipboardHotkeyConflictsWithWindowsKeybind`).

**Owner check** (stage 4): leave Clipboard off and confirm there is no `~/Library/Application Support/Mooring/Clipboard/` folder; turn it on, copy text, an image and a file, open ⇧⌘C, search, pin, and paste with ⌥Return (with Accessibility it pastes; without, it copies and the footer hint shows); copy a password from 1Password and confirm it doesn't appear; check that `mooring --help`, `mooring mcp` `tools/list` and Shortcuts show nothing clipboard-related; open the Clear alert over the dropdown and check the popup's placement and timing.

### 4.8 Settings and popup, as built

- **Dropdown, Clipboard ›.** While off, **Turn On…** only (it needs no permission). While on: the 10 most recent **unpinned** items, one line cut to 50 characters (an untitled image reads "Image", any other untitled copy "Item"), numbered ⌘1–⌘9 as the popup numbers its unpinned items (pins stay in the popup); a separator; **Pause Recording**; **Ignore Next Copy**; **Clear**, with **Clear All** as its ⌥ alternate (`NSMenuItem.isAlternate`, so it swaps while the submenu is open), both confirmed unless "don't ask again" is set; a separator; **Search… ⇧⌘C**, showing the live chord. The submenu is rebuilt each time it opens.
- **Settings → Clipboard**, three pages, each with a "Clipboard is off" banner and **Turn On…** while off (History adds **Delete Clipboard History…** when history is saved, 4.4): **History** (the on/off switch, history size 10–999 with a default of 200, "Clear history on quit", "Paste automatically", "Paste without formatting", and the popup hotkey recorder), **Ignore Rules** (ignored apps with an Add App… picker, ignored pasteboard types, ignore regexes, and "Record copies from your other devices (Universal Clipboard)", off) and **Appearance** (popup position, pinned items position, search field, preview, image height). Only keys ClipKit reads are shown. Maccy's "Ignore all apps except listed" stays hidden on purpose: with the password-manager default list it would flip into recording only password-manager copies. A test checks no Settings source names it and no page edit sets it.
- **General → Shortcuts** gains a "Clipboard popup" row (or a note while Clipboard is off), included in the conflict checks.

## Appendix

### A. Distribution and updates

- **No paid Apple account (decided 2026-09-29).** Mooring ships on GitHub only, not the App Store, and without Developer ID signing or notarization. Two install paths:
  1. **Build from source (recommended for developers):** `git clone` then `make install`, which builds with Xcode using the developer's own free Apple ID (personal team). Apps built locally aren't quarantined, so Gatekeeper never warns, and the signature is stable across rebuilds.
  2. **Prebuilt download:** `Mooring-<version>.zip` on GitHub Releases, signed with the maintainer's own certificate (`Config/Local.xcconfig`). On first open macOS blocks it; the README shows the fix: System Settings → Privacy & Security → Open Anyway, or `xattr -dr com.apple.quarantine /Applications/Mooring.app`.
- **Consequences of skipping Developer ID:**
  - Official Homebrew casks now reject apps that fail Gatekeeper (Chai is being removed for this), so Homebrew means a project tap only.
  - The helper's caller check (1.5) pins the signing certificate's hash instead of a Team ID.
  - Accessibility grants (levels 3 and 4) are tied to the signature, so the signing identity must stay the same across updates or users re-grant after every update.
- **Spike before level 1 build-out:** confirm that `SMAppService.daemon` registers and runs a helper signed with your own certificate on macOS 14, 15 and 26 (the owner's M4 Pro runs 26). If it doesn't, lid mode falls back to a one-time `sudo mooring install-helper` that installs a launchd daemon the classic way.
- **Updates (as built, stage 5):** Sparkle 2.10.0 with an EdDSA-signed appcast on GitHub Pages (`https://eidanerlich.github.io/mooring/appcast.xml`); Sparkle's own signature check works without Developer ID. The update check is the only network access and is opt-in on first launch. **The updater is gated on the public key:** `MOORING_SPARKLE_PUBLIC_KEY` (in `Config/Local.xcconfig`, empty by default) becomes `SUPublicEDKey`. With no key, no updater object is created, the Updates settings are hidden and Mooring never touches the network, so local builds and CI are always offline. With a key, the first launch asks once ("Check for updates automatically?", **Check Automatically** or **Not Now**); nothing is checked until the user agrees. Settings → Advanced then has "Check for updates automatically" and **Check Now**. `SUEnableAutomaticChecks` is `NO` in `Info.plist`, so Sparkle never prompts or schedules by itself. **Gentle reminders:** Mooring has no Dock icon and can't be Cmd-Tabbed to, so a scheduled update Sparkle would show behind other apps is easy to miss. Mooring's `SPUStandardUserDriverDelegate` lets Sparkle show a scheduled update only when it would be in immediate focus; otherwise Mooring posts a notification ("Mooring <version> is available", "Open the menu bar icon to update.") and adds **Update Available…** after Settings… in the dropdown, which calls Check Now to bring the update forward. Looking at the update, or the update session ending, clears both. This matters from 0.1.0 on: the installed binary is the one that presents every later update. Mooring and its scripts never generate or read the private key; it stays in the owner's Keychain (`docs/RELEASING.md`). Build-from-source users update with `git pull && make install`.
- **Uninstall (as built, stage 5):** Settings → Advanced → **Uninstall Mooring…** opens a confirmation sheet that lists the steps and has an "Also delete clipboard history" checkbox (off by default). Steps, in order:
  1. end every lease, so sleep returns to normal;
  2. turn lid sleep back on (`disablesleep 0` through the helper);
  3. unregister the helper (`SMAppService`);
  4. unregister the login item;
  5. remove `~/.local/bin/mooring` if it links to this app;
  6. remove the Claude Code plugin the app installed;
  7. remove the Claude Desktop and Cursor MCP entries Mooring added;
  8. delete `…/Mooring/Clipboard/`, only if ticked;
  9. delete `leases.json`, `layouts.json` and `mooring.sock` from `~/Library/Application Support/Mooring/` by exact name, and the folder only if it is then empty (so an unticked `Clipboard/`, or anything else, keeps it);
  10. delete Mooring's settings domains (`dev.mooring.windows`, `dev.mooring.clipboard` and the app's own), and delete them again in `applicationWillTerminate`, so a key AppKit or Sparkle writes on the way out doesn't bring a domain back;
  11. move the app to the Trash (`NSWorkspace.recycle`), then quit.

  A failing step doesn't stop the rest; the failures are listed in an alert before Mooring quits. If step 2 failed, the alert adds "Sleep may still be disabled. Run in Terminal: sudo pmset -a disablesleep 0". Cancel does nothing, and a second click while it runs is ignored. The Advanced page's caption lists what is removed rather than claiming "everything".
- **Release (as built, stage 5):** `scripts/release.sh` builds `dist/` (zip, `.sig`, `appcast.xml`, `homebrew/mooring.rb`) and publishes nothing; the owner's steps are in `docs/RELEASING.md`. The Homebrew cask is for the project tap `EidanErlich/homebrew-tap`; it declares `auto_updates true` (Sparkle updates the app), quits `dev.mooring.app` on `brew uninstall`, zaps `~/Library/Application Support/Mooring` and the three preference plists (`dev.mooring.app`, `dev.mooring.windows`, `dev.mooring.clipboard`), and its caveats give the quarantine advice above (Open Anyway, or `xattr -dr com.apple.quarantine /Applications/Mooring.app`).

### B. Open questions

Decided 2026-09-29: name **Mooring**, repo `github.com/EidanErlich/mooring`; GPL-3.0; plain-snapshot vendoring with provenance docs; anchor icon (outline off, filled on); agents act automatically by default, lid mode for agents asks each time (superseded by stage 2c-1: by default only open-ended agent requests ask); lid mode on battery behind an explicit opt-in; no clipboard encryption beyond Maccy's; development is staged (Build brief below).

- [x] Does launchd refuse to start a `dev.mooring.helper` binary that a user-level process swapped inside the (user-writable) app bundle? **Yes** (stage 1c, 2026-10-01, macOS 26.3.1): an ad-hoc-signed probe swapped in for the helper never ran; launchd logged `OS_REASON_CODESIGNING | Launch Constraint Violation` and AMFI `Constraint not matched`. No local path to root. Side effect worth knowing: after the refusal launchd marked the job `needs LWCR update` and would not spawn even the restored genuine helper until it was unregistered and approved again (and overwriting a signed binary in place spoils the kernel's signature cache: replace the file instead).
- [ ] Is the 2-minute grace after `Stop` long enough for background shells Claude starts? Measure on real sessions in stage 2.
- [x] Keep Loop's `Luminare` settings UI, or rebuild the Windows pages in plain SwiftUI for consistency? **Keep Luminare** (owner decision, 2026-10-03). The six pages are hosted in the Settings detail area; while Windows is off each shows only a "Windows is off" banner (see Engineering decisions, stage 3a).
- [x] Does `SMAppService.daemon` accept a personal-team-signed helper on macOS 26? **Yes** (stage 1a spike, 2026-09-30, macOS 26.3.1): registered from the Debug build in DerivedData, approved once in Login Items & Extensions, flipped `disablesleep` with no password, kept accepting a rebuilt app, and after `sudo launchctl kickstart -k system/dev.mooring.helper` launchd respawned the rebuilt (hardened-runtime) helper binary, which answered with no re-approval. The `sudo mooring install-helper` fallback is not needed. Not yet observed: a reboot, and a certificate renewal.

### C. Milestones

| Level | Ships | Gate before the next level |
| --- | --- | --- |
| 1 Core awake | One icon, no password, lid mode + guardrails; first public release | Force-kill restores sleep within 15 s |
| 2 CLI and agents | `mooring` CLI + socket, Claude Code plugin, MCP server | Mac sleeps within 2 min after Claude stops |
| 3 Windows | Loop as WindowKit, `mooring win` commands | With Windows off, no permission is requested |
| 4 Clipboard | Maccy as ClipKit, no agent API | No clipboard route from any CLI, MCP, intent or URL |

Level 1 alone replaces both Chai and Awayke and is worth releasing on its own; each later level starts only after the previous gate test passes on a real MacBook.

## Build brief for agents

This section tells a coding agent exactly how to build Mooring. Read the whole spec first, then build only the stage you are given, and stop at that stage's owner checkpoint.

### Project facts

| Item | Value |
| --- | --- |
| Owner | Eidan Erlich, GitHub `EidanErlich` |
| Repo | `github.com/EidanErlich/mooring` (private for now; decided 2026-09-30) |
| License | GPL-3.0-only; upstream MIT notices kept |
| App name / CLI | Mooring / `mooring` |
| Bundle IDs | App `dev.mooring.app`; helper `dev.mooring.helper` (also its Mach service name); CLI `dev.mooring.cli` |
| Dev and test machine | MacBook Pro, Apple M4 Pro, macOS 26 (Tahoe) |
| Deployment target | macOS 14 |
| Toolchain | Xcode 26 (26.6 as of 2026-09-30); Swift 6 language mode with strict concurrency |
| Signing | Free Apple ID personal team (Apple Development certificate); no Developer ID, no notarization |

### Repository setup

- **Project generation:** XcodeGen from `project.yml`. The generated `Mooring.xcodeproj` is gitignored, so agents never hand-edit a `.pbxproj`.
- **Targets:** `Mooring` (app); `MooringHelper` (command-line tool embedded at `Contents/MacOS/dev.mooring.helper`, launchd plist at `Contents/Library/LaunchDaemons/dev.mooring.helper.plist`); `mooring` CLI (target `MooringCLI`, product name `mooring`, embedded at `Contents/Helpers/mooring`; not in `Contents/MacOS`, where it would collide with `Mooring` on case-insensitive volumes); local packages in `Packages/`; unit test targets per package.
- **Signing config:** `Config/Local.xcconfig` (gitignored) holds `DEVELOPMENT_TEAM`; `Config/Local.xcconfig.example` is committed. A build-phase script writes the helper's allowed-client requirement from the app's signing certificate hash, so no team ID is hardcoded.
- **Dependencies (Swift Package Manager, pinned):** Defaults, KeyboardShortcuts, Sauce (stage 1–4), Sparkle (stage 5), Luminare and Scribe only if stage 3 keeps them.
- **CI:** GitHub Actions on a macOS runner: bootstrap, unsigned build (`CODE_SIGNING_ALLOWED=NO`), unit tests. Nothing that needs the helper, lid or permissions runs in CI.

```
make bootstrap    # brew install xcodegen swiftlint; xcodegen generate
make build        # Debug build of the Mooring scheme
make test         # all unit test targets
make build-release # Release build only
make install      # Release build to /Applications (Settings → General → Install command-line tool creates the ~/.local/bin/mooring symlink)
make reset-sleep  # sudo pmset -a disablesleep 0 (manual safety valve)
make uninstall    # quit Mooring, remove ~/.local/bin/mooring if it links into the installed app, remove the app (the in-app Uninstall Mooring… also does the helper, login item and settings)
make release      # build dist/ (zip, appcast, cask) with your Local.xcconfig identity and Sparkle key; publishes nothing
```

### Vendoring (plain snapshots)

Code is copied without git history, from these exact commits:

| Repo | Commit | Commit date | License |
| --- | --- | --- | --- |
| [Awayke](https://github.com/daemonphantom/Awayke) | `b502251` | 2026-08-24 | MIT |
| [Chai](https://github.com/lvillani/chai) | `61ec7d2` | 2026-04-05 | GPL-3.0-only |
| [Loop](https://github.com/MrKai77/Loop) | `0ac6d83` | 2026-09-29 | GPL-3.0 |
| [Maccy](https://github.com/p0deje/Maccy) | `c376789` | 2026-09-04 | MIT |

- Keep every copied file's original header. Changed files get a first line: `// Adapted from <repo>@<commit>: <original path>`.
- `THIRD_PARTY/<Repo>/` holds the upstream `LICENSE` and an `UPSTREAM.md` with the repo URL, commit, date, license, every file taken with its new path, and a list of modifications.
- `README.md` has a Credits section linking all four repos.
- Never copy: Chai's icons (Glyphish license), Loop's and Maccy's app icons, updaters, App Store review prompts.

### File map

**Awayke → AwakeKit and Helper (stage 1)**

| Upstream file | Destination | Change |
| --- | --- | --- |
| `Awayke/LidMonitor.swift` | `Packages/AwakeKit/LidMonitor.swift` | None |
| `Awayke/BatteryMonitor.swift` | `Packages/AwakeKit/BatteryMonitor.swift` | None |
| `Awayke/AutoOffPolicy.swift` | `Packages/AwakeKit/Sources/AwaykeMonitors/AutoOffPolicy.swift` | Override removed. The thermal and battery-opt-in rules live in AwakeKit's `target(...)`, which uses this policy for the low-battery hysteresis (stage 1c) |
| `Awayke/LidSessionTracker.swift` | `Packages/AwakeKit/LidSessionTracker.swift` | None |
| `Awayke/DisplayWakeKeeper.swift` | `Packages/AwakeKit/Assertions.swift` | Merge with a system-sleep assertion |
| `Awayke/HelperManager.swift` | `App/Helper/HelperClient.swift` | Add heartbeat and status read |
| `AwaykeHelper/main.swift`, `AwaykeHelperProtocol.swift`, both plists | `Helper/` | Add caller check, watchdog, heartbeat (1.5, 1.6) |
| `Awayke/PowerManager.swift`, `AutoOffTimer.swift`, `.github/workflows/release.yml` | Reference only | osascript fallback dropped; timers replaced by lease expiry; signing steps removed |

**Chai (stage 1):** reimplemented, not copied. Reference `ActivationSpecs.swift` (durations), `PowerAssertion.swift` (assertion calls) and `ChaiApp.swift` (wake handling, launch at login via `SMAppService.mainApp`).

**Maccy, stage 4:** Maccy's floating panel is adapted as `App/UI/ClipboardPanel.swift` (with its Maccy-state half in ClipKit's `ClipKitPopup`) for the Clipboard popup. The dropdown itself is an `NSMenu`, not a panel.

**Loop → WindowKit (stage 3)**

- Take: `Window Management/`, `Window Action Indicators/` (radial menu, preview window), `Core/` except `URLCommandHandler.swift`, `Utilities/`, `Extensions/`, `Private APIs/`, `Stashing/` (compiled but switched off), and the settings pages under `Settings Window/Settings/` and `Settings Window/Theming/`.
- Leave: `Updater/`, `LoopUpdaterHelper/`, `LoopDockTile/`, `Migration/`, `Icon/`, `Resources/AppIcon-*`, `Core/URLCommandHandler.swift` (replaced by `mooring win`).
- **As built (3a):** Loop@0ac6d83 sits at `Packages/WindowKit/Sources/WindowKit/Loop/` (135 source files, plus the `loop` symbol and `Localizable.xcstrings` as resources) and all six of Loop's unit tests under `Tests/WindowKitTests/Loop/`. Taken beyond the list above: `Accent Color/`, `Core/Multitouch/`, and `Settings Window/Loop/` (Advanced, Excluded Apps), with `SettingsContentView`, `SettingsTab` and `SettingsWindowManager` adapted. Left out beyond the list: the About page, the Icon page, onboarding, Loop's own status item, the `Updater` and `IconManager` calls in `LoopManager`, `App/` (wiring reference only), `Shared/PrivilegedInstallerProtocol.swift`, and Loop's app icons and `Credits` assets. `THIRD_PARTY/Loop/UPSTREAM.md` has the full list and every modification.

**Maccy → ClipKit (stage 4)**

- Take: `Models/`, `Observables/`, `Views/`, `Extensions/`, `Storage.swift`, `Storage.xcdatamodeld`, `Clipboard.swift`, `Search.swift`, `Sorter.swift`, `HighlightMatch.swift`, `HistoryItemAction.swift`, `PasteStack.swift`, `KeyChord.swift`, `KeyShortcut.swift`, `KeyboardLayout.swift`, `Accessibility.swift`, `ApplicationImage.swift`, `ApplicationImageCache.swift`, `ColorImage.swift`, `Throttler.swift`.
- Leave: `Intents/`, `SoftwareUpdater.swift`, `AppStoreReview.swift`, `About.swift`, `MenuIcon.swift`, `Settings/` (rebuilt as Clipboard pages), `AppDelegate.swift` and `MaccyApp.swift` (reference only).
- Change the store path to `~/Library/Application Support/Mooring/Clipboard/`.
- **As built (stage 4):** Maccy@c376789 sits at `Packages/ClipKit/Sources/ClipKit/Maccy/` (87 source files, English strings and the two sounds as resources) beside Mooring-written ClipKit files (`ClipKit.swift`, `ClipKitPopup.swift`, `PopupPanel.swift` and others), with all ten of Maccy's test files (91 tests) under `Tests/ClipKitTests/Maccy/`. `GlobalHotKey.swift` and both `.xcdatamodeld` files are left out (unused upstream), and `FloatingPanel` is replaced by a `PopupPanel` protocol plus the app's `ClipboardPanel`. `THIRD_PARTY/Maccy/UPSTREAM.md` has the full list and every modification.

### Menu-bar icon

- Off is a dimmed outline anchor; awake is a solid template pill (anchor, LID tag, kind label cut out); attention is an orange "!" pill. See the UX section's Icon states.
- If SF Symbols on macOS 26 includes an anchor, use it and its `.fill` variant. Otherwise draw an original vector: `MenubarAnchor` and `MenubarAnchorFill` in `Assets.xcassets`, 18 × 18 pt, rendered as template images.
- App icon: a placeholder anchor on a rounded square until a designed icon exists.

### Engineering decisions (authoritative)

If anything earlier in this spec conflicts with this subsection, this subsection wins.

**Languages and packages**

- First-party code (App, Helper, CLI, the `AwakeKit` and `MooringIPC` targets) uses Swift 6 with strict concurrency.
- Swift language mode is set per SwiftPM target, not per file, so vendored code lives in its own targets set to `swiftLanguageModes: [.v5]`: `AwaykeMonitors` (inside the AwakeKit package: `LidMonitor`, `BatteryMonitor`, `LidSessionTracker`, `AutoOffPolicy`), `WindowKit`, `ClipKit`. `AwakeKit` depends on `AwaykeMonitors`. Minimal edits to compile (`@unchecked Sendable`, `nonisolated(unsafe)`) are allowed and logged in `UPSTREAM.md`.
- SwiftPM layout is standard: `Packages/<Package>/Package.swift`, `Sources/<Target>/`, `Tests/<Target>Tests/`. The Awayke file-map destinations therefore mean `Packages/AwakeKit/Sources/AwaykeMonitors/<File>.swift` for the four files above and `Packages/AwakeKit/Sources/AwakeKit/` for the rest.
- **One `Defaults` version for the whole app: 9.x** (decided 2026-09-30). Loop requires Defaults ≥ 9.0 and Maccy pins 8.2.x; SwiftPM links only one version, so the app, WindowKit and ClipKit all use 9.x.
- Awayke's `AutoOffPolicy` has a manual-override input (`overridden`, `shouldKeepOverride`) and tests for it. Mooring has no one-off override (see Guardrail settings), so the port drops both.
- Tests use Swift Testing. Awayke's custom-runner tests are ported to it. `make test` runs `swift test` in each package plus `xcodebuild test` for the app scheme. Stage 0 adds one trivial test per package so the command passes.
- The app's `Info.plist` sets `LSUIElement = YES` (no Dock icon).
- SwiftLint runs via `make lint` and as a non-blocking CI step: default rules, `line_length` warning at 140, vendored targets excluded.
- CI uses the newest macOS runner image GitHub offers (at least `macos-15`) with its default Xcode; the macOS 14 deployment target keeps that compatible.

**Helper and signing**

- `Helper/Shared/MooringHelperProtocol.swift` is compiled into both the app and the helper. `MooringIPC` holds only the socket format, so the helper has no dependencies.
- `scripts/write-helper-requirement.sh` runs as a pre-build phase of `MooringHelper`: it takes the SHA-1 of the signing certificate from `EXPANDED_CODE_SIGN_IDENTITY` and writes `identifier "dev.mooring.app" and certificate leaf = H"<sha1>"` into the helper's `SMAuthorizedClients`, in a plist embedded with `-sectcreate __TEXT __info_plist`. The helper reads it back at launch and passes it to `setConnectionCodeSigningRequirement`; there is no generated Swift constant. Ad-hoc and unsigned builds (CI, `CODE_SIGNING_ALLOWED=NO`) get the placeholder `MOORING_UNSIGNED`, and the helper then refuses every connection, so no compile flag is needed.
- **Spike fallback (stage 1a, only if `SMAppService` registration fails):** stage 1a also builds a minimal `mooring install-helper` that copies the helper to `/Library/PrivilegedHelperTools/dev.mooring.helper`, writes `/Library/LaunchDaemons/dev.mooring.helper.plist` (same label and Mach service), and runs `launchctl bootstrap system` on it, under `sudo`.
- **Stage 1a debug control:** in Debug builds only, right-clicking (or Control-clicking) the icon shows a native `NSMenu` with the helper status, "Approve lid mode…" until the helper is enabled, "Disable lid sleep", "Enable lid sleep" and "Read SleepDisabled" (disabled until approval), and Quit. Stage 1b replaces it with the dropdown menu.

**Core types (AwakeKit)**

```swift
struct AwakeLevel: Codable, Hashable {       // idle system sleep is always prevented while any lease is live
  var display: Bool                          // keep the screen on
  var lid: Bool                              // survive lid close (helper)
}
// CLI/MCP --level: system = {false,false}, display = {true,false}, lid = {false,true}, "display,lid" = both.
// Lid does NOT imply display; they are independent toggles, matching the UX.

enum LeaseOwner: Codable, Hashable { case menu, cli(pid: Int32), agent(name: String), mcp(client: String) }

struct WatchedProcess: Codable, Hashable { var pid: Int32; var startTime: Date }  // start time guards against PID reuse on restore

struct Lease: Codable, Identifiable {
  let id: String; let owner: LeaseOwner; var reason: String; var level: AwakeLevel
  var expiresAt: Date?        // nil = until turned off / released
  var watch: WatchedProcess?
  var ttl: TimeInterval?      // the TTL last granted, so `renew` without --ttl reuses it; nil in older leases.json files
  var endsOnLidOpen: Bool
  let createdAt: Date
}

enum Suspension: Equatable { case lidNeedsAC, lowBatteryLid, lowBatteryAll, thermal }

struct TargetState: Equatable {
  var systemAssertion: Bool; var displayAssertion: Bool; var lidSleepDisabled: Bool
  var suspensions: Set<Suspension>
}

// Pure function; the reconciler applies its output.
func target(leases: [Lease], power: PowerSnapshot, thermal: ProcessInfo.ThermalState,
            lidClosed: Bool?, settings: AwakeSettings, now: Date) -> TargetState
```

```swift
struct PowerSnapshot: Equatable {
  var onAC: Bool
  var batteryPercent: Int?          // nil on Macs without a battery
}

struct AwakeSettings: Codable, Equatable {
  var clickLevel = AwakeLevel(display: false, lid: false)   // what left click turns On with
  var clickDuration: TimeInterval? = nil                    // nil = until turned off
  var endMenuLeaseAfterSleep = false
  var allowLidOnBattery = false                             // set by the opt-in sheet
  var lidBatteryThreshold: Int? = 20                        // nil = off
  var allBatteryThreshold: Int? = 10                        // nil = off
  var thermalCutoff = true
  var agentKeepAwake: AgentMode = .automatic                // .automatic, .explicit ("Only when asked")
  var agentLidApproval: AgentLidApproval = .askWhenOpenEnded // .askWhenOpenEnded, .alwaysAsk, .alwaysAllow, .never
  var agentSessionLid = true                                // Claude Code sessions use lid level
  var agentLidAlwaysAllowed: [String] = []                  // agent names allowed lid mode without asking
  var agentNotifications = true                             // agents may post notifications (`notify`)
  var agentWindows: AgentWindowMode = .automatic            // .automatic, .askFirst, .off
  var agentWaitingTimeout: TimeInterval = 1800              // 10, 30 or 60 min; a permission prompt holds this long
}
```

- **Suspensions** are engine state; leases are never modified by guardrails. They show in the status line and as the orange attention pill. Thermal compares `ThermalState.rawValue` (`.serious` or worse suspends lid; back to `.nominal` resumes). Low-battery-all resumes when on AC. Low-battery-lid resumes on AC at threshold + 5%. `target(...)` takes one more input, `suspended` (the previous suspensions), because hysteresis needs memory; the engine passes its current `state.suspensions` (stage 1c).
- **Guardrail settings:** lid threshold 20% and all-leases threshold 10% by default; each can be set to Off. There is no one-off override beyond these settings and the lid-on-battery opt-in.
- **Lease ids:** `menu`, `lid-session` (until I open the lid), `app-<pid>` (while an app runs), `anchor-<pid>` (`mooring anchor`), `claude-<session_id>`, `mcp-<slug>-<server pid>-<n>` (MCP clients only). There is no `timer` id; durations are `expiresAt` on the `menu` lease. The dropdown's *menu session* is either the `menu` lease or one or more `app-<pid>` leases, never both; the On toggle and left click end the whole session, and `mooring on` and `mooring off` act on that same session. `cli` is no longer an active id: it stays reserved, and `mooring off` ends one an earlier build left.
- **Naming:** the UI says "Until turned off" (never "Forever"); code uses `expiresAt == nil`. The wake setting is named "End my session after the Mac sleeps" (default off); it ends the menu session (the `menu` lease whatever its duration, and any picked apps) and never touches agent leases.
- `leases.json` is written with mode `0600`.

**UI details for stage 1b**

- **Clicks:** set `statusItem.button.sendAction(on: [.leftMouseUp, .rightMouseUp])` and branch on `NSApp.currentEvent`; Control-click counts as right click.
- **Dropdown menu:** an `NSMenu` with hosted SwiftUI rows, 300 pt wide. The status item's `menu` is set only for the click that opens the dropdown and cleared when the menu closes, so a left click still reaches the click handler. Clicks on hosted rows run their action without closing the menu. Disabled items can't be highlighted, so only the pure-text rows are disabled.
- **"While an app runs…"** lists `NSWorkspace.shared.runningApplications` with `activationPolicy == .regular`, with icons.
- **Settings window:** plain SwiftUI `NavigationSplitView` with the sidebar from the UX section. Items from 1.9 map to: helper, AC requirement, thresholds, thermal → Awake › Lid & Battery; notifications → General; logs, diagnostics, uninstall → Mooring › Advanced. Luminare is used only for the Windows pages in stage 3.
- **Defaults:** global On/Off hotkey none; ⇧⌘C is registered only while Clipboard is on (4.8). Notification permission is requested the first time lid mode or a guardrail notification is needed.
- **Icon:** SF Symbols on macOS 26 has no anchor symbol (checked 2026-09-30: `anchor`, `anchor.fill` and `anchor.circle` don't resolve), so stage 0 ships custom template assets. The badge symbols and the 5 pt dot described for stages 1b/1c are superseded by the menu-bar icon redesign (2026-10-01).
- **Stage 1b scope** (decided 2026-09-30):
  - The lid rows ("Until I open the lid", "Allow lid close"), the Lid & Battery and Advanced settings pages ship in stage 1c (icon states were later redesigned, 2026-10-01) with the lid level.
  - The dropdown's Windows and Clipboard submenus appear with stages 3 and 4.
  - The global on/off hotkey and the Shortcuts page come later (the default is none).
  - The status line reads `Off`, `On · until turned off`, `On · 1h 12m left`, `On · screen on · 1h 12m left` or `On · while Xcode runs`; it describes the lease that ends last. Countdowns round minutes up.
  - Anchored-list owner labels: Menu bar, Terminal, the agent's name, the MCP client's name.
  - The placeholder app icon is `App/Icon/AppIcon.svg`, rendered by `scripts/make-app-icon.swift`.

**Stage 2 details**

- **Socket protocol:** request `{"v":1,"id":"<uuid>","op":"acquire|renew|release|status|hook|notify|approve.wait|win.list|win.arrange|win.undo|win.layout","args":{…}}`; response `{"v":1,"id":"…","ok":true,"result":{…}}` or `{"v":1,"id":"…","ok":false,"error":{"code":"bad_request|guardrail|denied|not_found|internal","message":"…"}}`. Exit codes: `bad_request` and `not_found` → 1, `guardrail` or `denied` → 2, app unreachable → 3, `internal` → 4. A lid approval holds the connection open for up to 60 s, and `approve.wait` stays reserved but unused because the acquire itself waits. `LeaseInfo.pendingApproval` and `StatusResult.notifications` (`allowed`, `notDetermined` or `denied`) are additive and decode leniently.
- **Hooks:** the plugin's hooks all run `mooring hook <Event>`, which forwards the event over the socket as the additive protocol-v1 op `hook` (`args: {event, sessionId, cwd, notificationType?, agentID?, agentType?, runningBackgroundTasks?, watchPid?, toolTimeout?}`, result `{action}`; unknown fields are ignored). The decision lives in `HookPolicy` in AwakeKit, a pure function `action(_ hook: HookEvent, settings:, leaseExists:) → HookAction`, where `HookEvent` bundles the event name, `notificationType`, `agentID`, `agentType`, the running background-task count and `toolTimeout` (the action is `acquire`, `renew`, `renewFor(seconds)`, `setExpiry(seconds)`, `releaseAfter(seconds)`, `releaseNow`, `ignore` or `skipped` for "Only when asked"); the request handler applies the action through the engine's acquire, `renew`, `shorten` and `release`, under the same caller policy as named leases. `hooks.json` registers every event in the 2.3 table; synchronous hooks time out at 2 s (`SessionEnd` at 1 s) and the rest are `async`. Hooks never launch the app: `mooring hook` sends with a 1.5 s reply limit and `launch: false`, and `mooring-hook` exits 0 when there is no `mooring`, which keeps hook cost under 50 ms. Auto-launch applies only to interactive CLI use.
- **MCP and links (stage 2c-2):**
  - **Wire additions** (all lenient, so the protocol stays `v: 1`): `AcquireArgs` gains `client` (set only by `mooring mcp`) and `untilOff` (`on` with no expiry, whatever the click duration); the op `notify` has `NotifyArgs {title, body?, client?}` and `NotifyResult {posted}`. There is no `AcquireKind.mcp`, `ReleaseKind.mcp` or `StatusArgs.client`: MCP leases are ordinary `lease` acquires with `client` set, the server filters `status` itself, and it releases only the ids it created.
  - **`mooring mcp` is hand-rolled** inside the CLI (`MCPMessage`, `MCPTools`, `MCPServer` in MooringCLICore); there is no separate server package and no SDK dependency. It supports protocol versions `2025-06-18`, `2025-03-26` and `2024-11-05`, and exits on stdin EOF.
  - **MCP identity:** `MCPClientName` (MooringIPC) maps `clientInfo.name` to the display name and slug; the display name is the owner. See 2.5.
  - **Links:** `MooringLink` parses; `LinkHandler` finds the sender app and calls the request handler in-process as an agent named after it.
  - **Shortcuts:** `IntentActions` calls the same handler as a person. `AwakeStatusEntity` is the `AwakeStatus` entity.
  - **Version:** this stage ships as 0.0.3 (`MARKETING_VERSION` and the plugin's `plugin.json`). `mooring --version` and the MCP `serverInfo.version` still reported `0.2.0-dev` here; since stage 6 they read `CFBundleShortVersionString` from the enclosing `Mooring.app` (found from the binary's real path), or "unknown" outside a bundle.
- **`mooring doctor` and MCP clients:** check 8, "MCP clients", is described under Settings → Agents → Other agents (MCP).
- **`mooring doctor` and notifications:** check 7, "Notifications", reads `notifications` from the app's `status` reply: ✓ "allowed", – "not asked yet", and ✗ "denied" or "alerts off" with the fix "System Settings → Notifications → Mooring" only when the setting could need to ask (anything except Always allow and Never); otherwise – "denied (not needed)" or "alerts off (not needed)".
- **CLI packaging:** the command-line logic lives in the `MooringCLICore` library target of `Packages/MooringIPC` (argument parsing with `swift-argument-parser`, the socket client, `anchor`, `doctor`), so tests drive it without a socket. `CLI/main.swift` is a thin entry point that builds the real environment and exits with the result.
- **`mooring doctor` and lid sleep:** doctor reads `SleepDisabled` from the app's `status` reply, which asks the helper. The CLI never runs `pmset`.
- **`mooring doctor` and Claude Code:** the plugin records the Claude Code major.minor it was tested with as `testedWithClaudeCode` in its `mooring.json`. Doctor finds `claude` (`PATH`, then `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`), runs `claude --version` and `claude plugin list --json` with a 3 s limit each, and reads `mooring.json` from the installed plugin's `installPath`. Its "Claude plugin" check passes for an enabled `mooring@mooring-app` or `mooring@mooring` (with both installed, either one enabled is enough), and is skipped with "couldn't check (claude plugin list failed)" when `claude` runs but the list fails or times out; its "Claude Code version" check is skipped with a note ("tested with 2.1; you have 2.2.0", marked –, exit code unaffected) when the major.minor differs, and when either value is unknown.

**Stage 3 additions to the Loop file map**

- Also take `Shared/`, `Core/Multitouch/` (needed for gestures), `Settings Window/Loop/` (Advanced and Excluded Apps pages; About is dropped), and adapt `SettingsContentView.swift`, `SettingsTab.swift` and `SettingsWindowManager.swift` into the Windows settings group. Use `App/` as wiring reference only.
- Dependencies: Luminare (imported by 36 Loop files, so it stays), Scribe (57 files), Defaults, Subsurface (7 files). Loop tracks Luminare, Scribe and Subsurface on their `main` branches with no committed `Package.resolved`, so stage 3 picks and pins exact revisions.
- Also take `Accent Color/` (wallpaper-derived accent colours, used by the radial menu theming), which the Take list above omits. `Core/LoopManager.swift` references `Updater` and `IconManager`; remove those calls when vendoring.
- Undo keeps the last 10 arrangements in memory (window id → previous frame); it is lost on quit.

**Stage 3b: agent windows decisions (as built)**

- **Ops and wire:** `win.list`, `win.arrange`, `win.undo` and `win.layout`, handled in the app; the CLI and MCP only relay. Wire types are `WinPlan`, `WinPlacement`, `WinPlacementResult`, `WinArrangeResult`, `WinListArgs {client}`, `WinListResult`, `WinLayoutArgs`, `WinLayoutResult` and `WinUndoArgs {client}` (lenient, so the protocol stays `v: 1`). `WinPlan.validated()` allows at most 32 placements, clamps frames to 0–1 and accepts the `@frontmost` sentinel for `win do`.
- **Components:** `WindowSystem` and the `WS*` types (WindowKit, public); `Arranger` (app, pure over `WindowSystem`, with the undo stack and layouts); `RequestHandler+Windows.swift` (gating and dispatch); the `mooring.window-approval` notification beside the lid approval one; `WinCommands` in MooringCLICore; five MCP window tools.
- **Matching:** exact name or bundle id, then prefix, then substring, case-insensitive; ties are `ambiguous`, with a `reason` naming apps or windows. A `title` matches exactly before by substring. With no `title`, the frontmost window is used. Regions are frame-only (`WindowRegion.offered`). `partial` compares size only. `left` and `right` screens are relative to the main screen.
- **Gating:** Windows state, then agent mode, checked again inside the arrange lock right before applying; one arrangement at a time; `win.list` and `win.undo` carry `client` so MCP calls are gated like any other agent request, and Off refuses an agent's list too. See 3.4 for the messages.
- **Timeouts:** Accessibility calls are bounded at 1.5 s by the process-wide timeout `WindowKit.start()` sets on the system-wide element, and per application and window element; `win list` and mutating CLI requests, and every MCP window tool, use a 120 s client.
- **Not listed:** accessory apps are excluded from `win list`.
- **Layouts:** `~/Library/Application Support/Mooring/layouts.json`.
- **Version:** 0.0.5 (`MARKETING_VERSION`). The plugin is 0.0.4 (its skill changed).

**Stage 3a: WindowKit decisions (as built)**

- **Vendored snapshot:** Loop@0ac6d83 at `Packages/WindowKit`, in Swift 5 language mode (plus the upcoming features Loop turns on). The app and the other packages stay Swift 6. Mooring-written WindowKit code (`WindowKit.swift`, `WindowKit+Actions.swift`, `Capabilities.swift`, `ScreenSwitchFrames.swift`, `WindowChord.swift`, `WindowSettingsPage.swift`) sits beside the `Loop/` folder. The vendored `Loop/` folders and Loop's tests are excluded from SwiftLint.
- **Pinned dependencies** (`THIRD_PARTY/Loop/UPSTREAM.md` has the revisions and reasons): Luminare and Subsurface by `revision`; Defaults `exact: "9.0.9"`, the same as the app; Scribe on `branch: "main"`, held at `6581808` by `Package.resolved`. Scribe cannot take a `revision:` pin because Subsurface requests `branch: "main"` and SwiftPM refuses two different revision-based requirements for one package.
- **Build:** Scribe uses Swift macros, so the Makefile passes `-skipMacroValidation` (CI builds non-interactively through `make`) and `-disableAutomaticPackageResolution`. The generated Xcode project is gitignored, so `Config/Package.resolved` is committed and `make generate` copies it into the project's `xcshareddata/swiftpm/`; builds then use exactly those pins. After a dependency change, regenerate that file from a resolved app build.
- **Loop's settings** live in the `dev.mooring.windows` `UserDefaults` suite with iCloud sync off (`dev.mooring.windows.tests` when running under a test host), never in Mooring's own defaults. There is no import from an existing Loop install.
- **Capabilities** are checked once, in `WindowKit.start()`, and fail closed. Each failure is logged once through `os.Logger` (subsystem `dev.mooring`, category `windows`). They cover window-id lookup, SkyLight moves, window details (corner radius, window level, display lookup), window effects (blur, capture) and MultitouchSupport (gestures: without it the gesture triggers don't start and the Gestures page shows "Gestures aren't available on this Mac"). Every private-API path (`@_silgen_name` replaced by `dlsym`) reads them; a failed one hides or disables its feature and never crashes. Stash and Focus are hidden in the pickers and settings and inert in the action engine.
- **`windowsEnabled`** is a plain `Bool` Defaults key, default false. `WindowsController` (`App/Windows/`) owns WindowKit and has four states: off, waitingForTrust, on and needsAccessibility. WindowKit is constructed only when Windows turns on, and a launch with Windows off creates no WindowKit object (`offMeansOff` checks `WindowKit.instantiatedSingletons`) and never probes Accessibility. After Turn On, trust is polled every 2 s for 5 minutes; while on, revocation is checked every 5 s and gives the attention reason "Windows needs Accessibility" (the pill is "!"; the reason shows as a line in the Windows submenu).
- **Dropdown, Windows ›:** while off, **Turn On…**; in needsAccessibility, the reason line, **Turn On…** and **Turn Off Windows** (waitingForTrust has the last two). While on: Left half, Right half, Maximize, Centre, Next screen, each with its chord as trailing text (a Loop chord cannot be a menu key equivalent, and a key equivalent would register a live shortcut); **More Actions ›** (both replaced by "Window actions aren't available on this version of macOS" when window-id lookup fails); and the **Window Manager** switch. Turn On and Turn Off Windows run after the menu closes. Actions apply to the app that was frontmost before the menu opened; if that is Mooring itself, they apply to Mooring's window.
- **Settings → Windows:** six Luminare pages (Behavior, Keybinds, Gestures, Radial Menu, Preview, Excluded Apps) hosted in the detail area. While Windows is not on, each page shows only the "Windows is off" banner with **Turn On…** (Behavior also keeps the Window Manager toggle, which reads on whenever Windows is wanted, including while it needs Accessibility), because building Loop's pages creates `SettingsWindowManager.shared` and Luminare views, which would break "loads none of WindowKit". So settings cannot be edited before turning Windows on.
- **General → Shortcuts:** lists Toggle On/Off (None by default), the Windows trigger key and every Windows keybind, or a note that Windows is off. Two Mooring shortcuts on one chord show "Also used by <other>". A chord that matches an enabled macOS shortcut shows "Used by macOS: <name>", read from `com.apple.symbolichotkeys` plus a built-in table of stock defaults for ids the plist does not list. A link points to Loop's advice on remapping Caps Lock; Mooring never remaps it.
- **Version:** 0.0.4 (`MARKETING_VERSION`); the plugin stayed 0.0.3 because its files did not change. The plugin changes version only when its files change, and `pluginVersionMatchesMarketingVersion` requires plugin ≤ marketing. (Stage 3b ships 0.0.5 with plugin 0.0.4.)

**Stage 4: ClipKit decisions (as built)**

- **Vendored snapshot:** Maccy@c376789 at `Packages/ClipKit`, in Swift 5 language mode; the app and other packages stay Swift 6. Exact pins: Defaults 9.0.9 (the same as the app, no edits needed), KeyboardShortcuts 2.0.2, Sauce 2.4.1, SwiftHEXColors 1.4.1, Fuse 1.4.0 and swift-log 1.6.4. Not taken: Sparkle, Settings, LaunchAtLogin. `GlobalHotKey.swift` and both `.xcdatamodeld` files are left out (unused upstream), and `FloatingPanel` is replaced by a `PopupPanel` protocol plus the app's `ClipboardPanel`.
- **Settings and store:** Maccy's settings live in the `dev.mooring.clipboard` suite (`dev.mooring.clipboard.tests` under a test host). The store is `~/Library/Application Support/Mooring/Clipboard/Storage.sqlite`, the folder at `0700` and excluded from backup. It is created only on start, and ClipKit falls back to an in-memory store if the folder can't be secured.
- **Off means off:** `clipboardEnabled` (Defaults, default false) is the switch. `ClipboardController` (`App/Clipboard/`) builds ClipKit only while on, so while off there is no recording, no store, no pasteboard polling and no hotkey. `popupView()` is empty while off, the modifier-flag and key monitors exist only while running, and a released ClipKit stops everything. A launch with Clipboard off creates no ClipKit singleton (`offMeansNoStoreNoPolling` checks `ClipKit.instantiatedSingletons`), and nothing starts under a test host.
- **Never recorded:** concealed, transient and auto-generated types; ignored apps; copies under Secure Keyboard Entry; Universal Clipboard (off by default); copies with more than 1,000 items or contents, which aren't recorded at all (4.5).
- **Privacy:** no clipboard contents in logs or notifications. ClipKit's logger writes ids and counts only, vendored `print` calls were replaced with path-free logs, and Maccy's `Notifier` is a no-op in Mooring. Tests use a uniquely named private pasteboard and prove `NSPasteboard.general` is untouched (a recursive test trait and an XCTest base class compare its change count).
- **Dropdown and popup:** see 4.8. Pasting needs Accessibility; without it an item is only copied (4.6). Clear and Clear All run Maccy's confirmation alert (its own strings, from ClipKit's resource bundle), and a "don't ask again" tick is saved only on a confirmed clear.
- **Settings and Shortcuts:** Settings → Clipboard has History, Ignore Rules and Appearance (4.8). The Shortcuts page's "Clipboard popup" row joins `ShortcutConflicts`; KeyboardShortcuts' own chord text is normalised through `ShortcutChord`, and its rendering of Space and F-keys may differ (`docs/BACKLOG.md`).
- **The agent wall:** nine app tests plus an MCP test, `NSAppleScriptEnabled` false, agent folders scanned for ClipKit and for clipboard, pasteboard and history names, every `App/` folder classified, and the MooringIPC manifest not mentioning ClipKit (4.3). `Op` is `CaseIterable` for it.
- **Version:** 0.0.6 (`MARKETING_VERSION`). The plugin stays 0.0.4 (its files did not change).

**Stage 4 additions to the Maccy file map**

- Also take `ItemsProtocol.swift`, `Notifier.swift`, `PinsPosition.swift`, `PopupPosition.swift`, `SearchVisibility.swift`, `Selection.swift`, `VoiceOver.swift`, and `Sounds/`. `GlobalHotKey.swift` and both `.xcdatamodeld` files are left out (see the as-built notes). `Intents/` has six files; all are left out.
- Dependencies: Defaults, KeyboardShortcuts, Sauce, swift-log, SwiftHEXColors, Fuse (fuzzy search). Maccy's Settings and LaunchAtLogin packages are not needed.
- Maccy pins Defaults 8.2.x; Mooring uses Defaults 9 (see Engineering decisions). The vendored code compiled against Defaults 9.0.9 without edits.
- Store file: `~/Library/Application Support/Mooring/Clipboard/Storage.sqlite`.
- Default ignored apps: 1Password 7 and 8, Bitwarden, Dashlane, LastPass, KeePassXC, Keychain Access and Passwords (the exact bundle ids are in ClipKit's `Defaults.Keys+Names.swift`).
- Skipping copies while Secure Keyboard Entry is on (`IsSecureEventInputEnabled()`) is new code, not in Maccy.

**Stage 5: release tooling (as built)**

Owner's standing instruction: keep it private. Everything to ship v0.1 is built and tested; **nothing is published**. No tag, GitHub Release, Pages deploy or tap repo exists, and no script runs one.

- **Sparkle:** 2.10.0, pinned exactly (`Config/Package.resolved`) and linked into the app only. The feed is `https://eidanerlich.github.io/mooring/appcast.xml`. The EdDSA private key stays in the owner's Keychain, never in the repo or CI; releases are signed on the owner's Mac. The Makefile's `-packageAuthorizationProvider netrc` stops SwiftPM looking in the Keychain for GitHub credentials when it downloads Sparkle's binary.
- **Key-gated updater:** `MOORING_SPARKLE_PUBLIC_KEY` (`Config/Shared.xcconfig`, empty; the owner sets it in `Config/Local.xcconfig`) feeds `SUPublicEDKey`. `UpdatesController` (`App/Updates/`) creates no updater and asks nothing when the key is empty, and makes the updater at most once when it is set. Tests use an injected `UpdaterDriving`, never real Sparkle or the network. The gentle-reminder decisions live in `UpdateReminder` (tested with a fake notification poster); `LiveSparkleUpdater` hands Sparkle's user-driver delegate calls to it. The Updates settings section appears only when an updater is available. `App/Updates` is classified as a non-agent folder in the agent wall test: the updater talks to Sparkle's feed only, never to the socket.
- **Uninstall:** see Appendix A. `Uninstaller` runs the steps through one `UninstallPerforming` seam; tests never build the real steps. `Uninstaller.removeSupportFiles(in:)` and `Uninstaller.summary(_:)` are tested on temporary folders and fake failures, and `SettingsDomainsRemover` with a recording closure. `make uninstall` also removes `~/.local/bin/mooring`, but only a symlink whose target is under `/Applications/Mooring.app/` (a sibling such as `Mooring.app.old` does not match), and its paths are quoted so a path with spaces works. `scripts/test-make-uninstall.sh` runs it against a temporary `HOME` and a stub `pkill`.
- **`scripts/release.sh`:**
  - Flags: `--dry-run --app PATH` (uses a built app; no tests, build or signing; the appcast signature is empty; the clean-tree and tag checks are skipped unless `--check-git` is also given), `--publish` (prints the tag, `gh release`, `gh-pages` appcast and tap commands and runs none of them; refused together with `--dry-run`), and `--check-git`.
  - A real run checks a clean tree and an unused tag, runs `make test`, builds Release (`make build-release`), refuses the build if its `SUPublicEDKey` is empty or if `codesign -dv` reports `Signature=adhoc` or no Authority or TeamIdentifier (`check_update_key`, `check_signature`), verifies with `codesign --verify --deep --strict`, zips with `ditto -c -k --sequesterRsrc --keepParent` (so a plain `unzip` leaves no `._` files inside the app), signs with Sparkle's `sign_update`, and writes the appcast and cask. A real run errors if the bundle has no `CFBundleVersion` or `LSMinimumSystemVersion`.
  - The **tag check is local only**: a tag that exists only on the remote is not caught.
  - Outputs, all in the gitignored `dist/`: `Mooring-<version>.zip`, its `.sig`, `appcast.xml` and `homebrew/mooring.rb` (a cask for `EidanErlich/homebrew-tap` with the zip's sha256, `auto_updates true`, `uninstall quit:`, `zap trash:` and caveats giving Appendix A's quarantine advice).
  - Makefile: `make release` runs the script with no flags (`make test` also runs `scripts/test-release.sh`); `make build-release` is the Release build that `make install` now depends on.
  - CI: a "Release dry run" step after the unit tests runs the dry run on the Debug app and checks that the zip, appcast and cask exist, that the appcast is well-formed XML and that the cask parses (`ruby -c`).
- **Version:** `MARKETING_VERSION` is **0.1.0**, and the plugin stays 0.0.4. `CURRENT_PROJECT_VERSION = $(MARKETING_VERSION)`, so `CFBundleVersion` (the appcast's `sparkle:version`) follows the marketing version and always rises with releases; Sparkle's comparator handles dotted versions. The build number is no longer independent, and nothing used it. The tag `v0.1.0` is **not** created: it is the owner's checkpoint.
- **Signing:** a release is signed with the maintainer's own certificate; keep the same one across releases so Accessibility grants survive updates; if it ever changes, the release notes tell users to re-grant.
- **Docs:** README has Install, Updates, Uninstall and a Releasing pointer; `docs/RELEASING.md` is the owner's publish checklist. Leftovers are in `docs/BACKLOG.md` ("Release (5 leftovers)").
- **Owner check:** generate the Sparkle keys (and back the private key up offline), put the public key in `Config/Local.xcconfig`, run `bash scripts/release.sh --publish` once and inspect the `dist/` it built; create `EidanErlich/homebrew-tap` and enable Pages; run the commands it printed (the first block tags v0.1.0), then verify the tag with `git ls-remote --tags origin`; clean-install on a second user account and confirm Gatekeeper's block and the quarantine fix. Also: `claude plugin marketplace remove mooring-app` (the Uninstall plugin step) also uninstalls the plugin; confirm that reads right.

**Gates between levels** (Appendix C, Milestones): a level is done only when its stages' owner checkpoints below have passed.

### Stages

Each stage is one branch and one pull request titled `Stage N: …`, and ends at its owner checkpoint.

| Stage | Builds | Agent verifies | Owner checkpoint |
| --- | --- | --- | --- |
| 0 Scaffold | Repo, `project.yml`, Makefile, CI, LICENSE, THIRD\_PARTY, README; an empty menu-bar app with the outline anchor | `make bootstrap build test` passes; CI green | Launches the app and sees the icon |
| 1a Helper spike | Minimal helper: register, set and read `disablesleep`, caller check; a debug menu item to flip it | `pmset -g \| grep SleepDisabled` flips between 1 and 0 | Approves the helper in System Settings. If registration fails, switch to the `sudo mooring install-helper` fallback |
| 1b Awake engine | Leases, reconciler, assertions, On defaults, the dropdown menu with the Awake section, General and Awake settings | Unit tests; `pmset -g assertions` shows Mooring's assertion; left click toggles | Uses it for a day |
| 1c Lid and guardrails | Lid level, watchdog, heartbeat, launch reset, battery and thermal guardrails, battery opt-in sheet | Scripted `kill -9` of the app returns SleepDisabled to 0 within 15 s | Closes the lid for 10 min with `ping -i 5 1.1.1.1 > ~/lidtest.log` running, on AC and on battery; checks the log has no gap |
| 2a IPC and CLI | Socket, all `mooring` commands in 2.2, `doctor`, CLI install, agent holds (`--watch-pid auto`, the "For agents" patterns), the dropdown lease-row fix (rows update in place by id) | `mooring anchor -- sleep 20` shows in `mooring status --json`; exit codes match 2.2 | None |
| 2b Claude Code plugin | The `hook` op and `HookPolicy`; `mooring hook`; the plugin (hooks, skill, `mooring-hook`) with an in-app and a GitHub marketplace; Settings → Awake → Agents; `doctor`'s plugin and Claude Code version checks | Recorded hook payloads piped to `mooring hook` acquire, renew and release a lease; the plugin files and both marketplaces validate | Installs the plugin from Settings; sees "Claude Code · <folder>" in the menu, the lease end after Claude stops or is killed, and the permission-prompt timeout (the lid-closed run waits for 2c-1's agent lid approval) |
| 2c-1 Lid approvals | `LidApproval`, agent detection, Allow once / Always allow / Deny notifications, session lid, Settings → Agents → Lid mode, `doctor`'s Notifications check | Handler tests with an injected approver; the deny path exits 2 | Closes the lid during a Claude task; clicks each notification button |
| 2c-2 MCP, links and Shortcuts | `mooring mcp` (`keep_awake`, `release_awake`, `awake_status`, `notify`) and `mooring notify`; the `mooring://` URL scheme; the three Shortcuts actions; Settings → Agents → Other agents (MCP) with Add/Update/Remove for Claude Desktop and Cursor and Copy config; `doctor`'s MCP clients check; version 0.0.3 | `MCPServerTests` drive the server over an in-memory pipe; handler, link, intent, config and CLI tests | Runs the Shortcuts, opens links from Raycast, adds Mooring to Claude Desktop and asks it to keep the Mac awake and to notify, and runs `mooring doctor` |
| 3a WindowKit (built, 0.0.4) | Vendored Loop@0ac6d83 as `Packages/WindowKit` with pinned dependencies and capability checks; `WindowsController` and the Accessibility flow; the dropdown's Windows › submenu; Settings → Windows (six Luminare pages); General → Shortcuts with conflict detection; version 0.0.4 | With Windows off, no Accessibility prompt and no WindowKit object created; frame-maths, capability, controller, submenu and shortcut-conflict tests; Loop's six tests pass | Grants Accessibility; tries the radial menu, keybinds, a cycle, drag-to-edge snapping and the preview; revokes Accessibility and sees the orange pill |
| 3b Agent windows (built, 0.0.5) | `win.list`, `win.arrange`, `win.undo` and `win.layout` in the app, with `mooring win list / arrange / do / undo / layout / list-regions`; five MCP window tools (9 in all); gating by Windows state and Settings → Agents → "Window arrangement by agents" (Automatic · Ask first · Off) with the `mooring.window-approval` notification; undo of the last 10 arrangements; saved layouts; the skill covers windows; version 0.0.5 (plugin 0.0.4) | `Arranger`, handler, CLI and MCP tests over a fake `WindowSystem`; the full suite passes | With Accessibility granted, arranges three TextEdit windows and undoes them; asks Claude for the Chrome / iTerm / Slack layout; tries Ask first (Allow, then Deny) and `win layout save` / `apply` |
| 4 ClipKit (built, 0.0.6) | Vendored Maccy@c376789 as `Packages/ClipKit`; `ClipboardController` and the off-by-default switch; the dropdown's Clipboard › submenu and the ⇧⌘C popup (`ClipboardPanel`); Settings → Clipboard (History, Ignore Rules, Appearance) and the Shortcuts row; ignore rules, never-recorded types, retention; the agent wall tests; version 0.0.6 (plugin unchanged at 0.0.4) | ClipKit's 91 Maccy tests plus its own tests on a private pasteboard that prove the real one is untouched; controller, submenu, settings and shortcut-conflict tests; `AgentWallTests` (9) and `AgentWallMCPTests` fail the build if any IPC op, MCP tool, intent, URL route or AppleScript path touches ClipKit; the full suite passes | Leaves Clipboard off and finds no store; turns it on, copies text, an image and a file, searches, pins and pastes; copies from 1Password and confirms it isn't recorded; times the popup |
| 5 Release (built, 0.1.0) | Key-gated opt-in Sparkle updater (2.10.0) with Check Now; Settings → Advanced → Uninstall Mooring… and a `make uninstall` that removes the CLI link; `scripts/release.sh` (zip, signature, appcast, Homebrew cask in `dist/`; `--dry-run`, `--publish` prints only) with `make release` and a CI dry run; README Install, Updates, Uninstall; `docs/RELEASING.md`; version 0.1.0 (plugin 0.0.4). Nothing is published | Updater, uninstall and release-script tests, including a dry run on a fixture app; the full suite passes | Follows `docs/RELEASING.md`: Sparkle keys, `scripts/release.sh --publish` (one build), tap repo and Pages, the printed publish commands, a clean install on a second macOS user account; tags v0.1.0 |

### Rules for agents

- Build only the assigned stage. At the end, list exactly what the owner must do for the checkpoint.
- Never leave sleep disabled: every test that touches lid mode sets `disablesleep 0` in teardown. `make reset-sleep` is the manual escape hatch.
- Only the helper runs `pmset`. The app and CLI never call it directly.
- Keep the helper under 250 lines with no dependencies.
- No network access in app code except Sparkle, from stage 5.
- Don't claim behaviour you couldn't observe (lid, battery, notifications, permission prompts); mark it "needs owner check".
- Swift 6 strict concurrency; `@MainActor` for UI and `AwakeEngine`; `os.Logger` with subsystem `dev.mooring`.
- Changes offered back to Loop must follow Loop's `AI_POLICY.md`.

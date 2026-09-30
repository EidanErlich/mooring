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
  App/                   # menu-bar app target: Sources/, UI/ (FloatingPanel), Helper/HelperClient.swift, Assets.xcassets, Info.plist
  Helper/                # privileged launchd daemon: main.swift, Shared/MooringHelperProtocol.swift, plists
  CLI/                   # `mooring` executable, incl. `mooring mcp` (stdio MCP server)
  Packages/
    AwakeKit/            # Package.swift, Sources/AwakeKit/, Tests/AwakeKitTests/ (level 1)
    MooringIPC/          # socket wire format shared by app and CLI (level 2)
    WindowKit/           # vendored Loop (level 3)
    ClipKit/             # vendored Maccy (level 4)
  Integrations/
    claude-code-plugin/  # .claude-plugin/plugin.json, hooks/hooks.json, scripts/mooring-hook, skills/mooring/SKILL.md, .mcp.json
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
| ⇧⌘C | Open the dropdown straight to Clipboard |

Settings → General can swap left and right click for people who want the dropdown on click.

**What On means** is set in Settings → Awake → "When I click the icon": level (system, screen on, or lid), duration (until turned off, or 30 min to 8 h), and "end after the Mac sleeps". Defaults: system level, until turned off.

**Icon states:** off (anchor outline), on (anchor filled), on + lid mode (filled anchor with a small closed-lid badge), lid mode on battery (battery badge), attention (dot: helper needs approval, guardrail paused lid mode, or permission missing).

### The dropdown is a custom panel, not a native menu

Like Maccy, the dropdown is a non-activating floating panel (Maccy's `FloatingPanel`, an `NSPanel` subclass) drawn in SwiftUI, anchored under the icon. That's what allows a live search field, countdowns and ✕ buttons, which native `NSMenu`s can't hold. Each section opens in place, like Control Center modules, with a ‹ back arrow.

```
 ● On · lid mode · 1h 12m left
 ─────────────────────────────────
 Awake                            ›
 Windows                          ›
 Clipboard                        ›
 ─────────────────────────────────
 Settings…                       ⌘,
 Quit Mooring                    ⌘Q
```

| Section | Contents |
| --- | --- |
| **Awake** | On toggle; durations (30 min, 1 h, 2 h, 4 h, 8 h, until turned off); until I open the lid; while an app is running…; keep screen on; allow lid close (on battery: confirmation the first time); **Anchored** list of every lease with owner, reason, time left and ✕ |
| **Windows** | The most-used actions with their shortcuts (halves, maximize, centre, next screen), More Actions, saved layouts (later), Window Manager on/off |
| **Clipboard** | Maccy's full view: search field focused on open, history list, pins, previews; Pause Recording, Ignore Next Copy, Clear History |

A module that's off shows a single **Turn On…** row that walks through its permission (Accessibility), so the dropdown keeps the same shape.

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
| For 30 min / 1 h / 2 h / 4 h / 8 h / Until turned off | `menu` lease with `expiresAt` (Chai's durations) |
| Until I open the lid | `lid` lease, `endsOnLidOpen = true` (Awayke's `LidSessionTracker`) |
| While an app runs… | Pick a running app; lease with `watch` |
| Keep screen on | Toggles `display` on the menu lease |
| Allow lid close | Toggles `lid` on the menu lease; until the helper is approved, this row is replaced by "Approve lid mode…", which calls register() and then opens Login Items & Extensions |

Defaults for a fresh install: click = `system` level, until turned off, lid off. Users who want Awayke-style one-click lid mode set the default level to `lid` in Settings.

### 1.4 Menu-bar icon and menu

Icon, click behaviour and dropdown contents are specified in **UX: one icon, one dropdown** above. In short: an anchor icon, outline when off and filled when on; left click toggles On with the user's defaults; right click opens the dropdown; the Awake section lists every active lease with its owner, reason, time left and ✕.

### 1.5 No password after first run: the privileged helper

The helper is a launchd daemon registered with `SMAppService.daemon(plistName:)` (macOS 13+), as Awayke does. First use of lid mode calls `register()`; macOS shows a notification, and the user approves it once in **System Settings → General → Login Items & Extensions**. From then on toggles are silent, across reboots. There is no osascript password fallback: if the helper isn't approved, the menu shows a single "Approve lid mode…" item that opens that pane.

**Helper surface (the whole of it):**

```swift
// Helper/Shared/MooringHelperProtocol.swift, compiled into both the app and the helper
@objc protocol MooringHelperProtocol {
  func setLidSleepDisabled(_ disabled: Bool, reply: @escaping (NSError?) -> Void)
  func lidSleepDisabled(reply: @escaping (Bool) -> Void)   // reads `pmset -g` SleepDisabled
  func heartbeat(reply: @escaping () -> Void)             // app calls every 30 s while lid mode is on (1.6)
  func version(reply: @escaping (String) -> Void)
}
```

It runs `/usr/bin/pmset` with a fixed argument array; no strings from the client reach a shell. Target size is under 250 lines, with no dependencies, so anyone can audit it.

**Caller validation, in two layers.** Awayke embeds an `SMAuthorizedClients` requirement in the helper's Info.plist but its listener accepts every connection. Mooring adds the check in code:

- `listener.setConnectionCodeSigningRequirement(req)` (macOS 13+), where `req` is `identifier "dev.mooring.app" and certificate leaf = H"<SHA-1 of the app's signing certificate>"`. A build script writes the hash into the helper at build time (Build brief → Engineering decisions). The same string goes in the helper's `SMAuthorizedClients`. Only the signed Mooring app can connect; the CLI and MCP server never talk to the helper directly.
- In `shouldAcceptNewConnection`, also check the connection's audit token with `SecCodeCopyGuestWithAttributes` + `SecCodeCheckValidity` against the same requirement.

### 1.6 Never stuck awake

`disablesleep` survives a crash, so cleanup can't live only in the app. Four layers:

1. **Helper watchdog.** The helper records whether it set `disablesleep 1`. When the app's XPC connection invalidates (quit, crash, force-kill), the helper waits 10 s for a reconnect, then sets it back to 0 on its own.
2. **App heartbeat.** While lid mode is on, the app pings the helper every 30 s. No ping for 90 s → the helper restores sleep. This catches a hung app whose connection is still open.
3. **Launch reset.** On launch the app asks the helper for the current value and resets it to 0 unless a restored lease needs lid mode (Awayke does the reset unconditionally).
4. **Quit and uninstall.** `applicationWillTerminate` restores sleep. "Uninstall helper…" in Settings restores sleep before calling `unregister()`.

### 1.7 Guardrails (enforced by the engine, not callers)

| Guardrail | Default | Behaviour |
| --- | --- | --- |
| Low battery, lid mode | On battery and < 20% | Suspend `lid` (keep `system`), notify; resume when back on AC and ≥ 25% (Awayke's hysteresis) |
| Low battery, all awake | On battery and < 10% | Suspend all leases, notify |
| Thermal | `ProcessInfo.thermalState` ≥ `.serious` while lid is closed | Suspend `lid`, notify; resume at `.nominal` |
| Lid mode on battery | Allowed, opt-in | Until the user opts in, lid mode applies only on AC. The first lid session on battery shows a confirmation sheet (battery drain, heat, keep it out of bags) with "Allow on battery". While it runs on battery, the icon carries a battery badge. |
| Max lease length | 12 h for any lease with an expiry; "Until turned off" allowed only from the menu | Longer requests are clamped and the clamp is reported to the caller |
| Agent cap | 4 h per agent lease, renewable | See Part 2 |

macOS still forces sleep at critical battery regardless of `disablesleep`; the guardrails act before that point. Battery state comes from `IOPSNotificationCreateRunLoopSource` (Awayke's `BatteryMonitor`), lid state from the `IOPMrootDomain` clamshell notification (Awayke's `LidMonitor`).

### 1.8 System events

- **Wake from sleep:** if "End my session after the Mac sleeps" is on (Chai's "disable after suspend"), end the menu lease. Agent leases are unaffected.
- **User switch / screen lock:** leases continue. Screen lock is expected in lid mode.
- **External display connect/disconnect:** no change needed; clamshell with a display already stays awake, and `disablesleep` covers the no-display case.

### 1.9 Settings window

Settings use the sidebar defined in the UX section, with the mapping in Build brief → Engineering decisions → UI details. Level 1 needs: launch at login (`SMAppService.mainApp`), click action and left/right swap, On defaults (level, duration, "End my session after the Mac sleeps"), helper status with approve and uninstall, lid-on-battery opt-in, battery thresholds, thermal cutoff, notification toggles, log level, reveal logs and export diagnostics. Values are stored with the `Defaults` package.

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
- **Protocol:** newline-delimited JSON, one request and one response per line, with a `v` field for versioning. Example: `{"v":1,"op":"acquire","id":"claude-abc123","level":"lid","ttl":900,"reason":"Claude Code: fix tests","watch_pid":4121}`.
- **App not running:** the CLI starts it with `open -gj -b dev.mooring.app` and waits up to 3 s for the socket. If that fails it exits with code 3 and a one-line error; it never falls back to `pmset` or `caffeinate` itself.
- **Why a socket, not XPC:** the CLI is also invoked from hook scripts and other tools' sandboxes; a socket is simpler to call from any language, and privilege stays inside the app.

### 2.2 CLI reference

The binary ships at `Mooring.app/Contents/MacOS/mooring`. Settings offers "Install command-line tool", which symlinks it to `/usr/local/bin/mooring` (or `~/.local/bin/mooring` without admin). Homebrew installs the symlink automatically.

| Command | Does |
| --- | --- |
| `mooring on [--level system\|display\|lid] [--for 2h] [--reason "…"]` | Acquire the `cli` lease (same as the menu click) |
| `mooring off` | End the `cli` lease |
| `mooring anchor [--level …] [--reason …] -- <command …>` | Lease tied to the child process; exits with the child's exit code |
| `mooring anchor --pid <pid> [--level …]` | Lease until that process exits |
| `mooring lease acquire <id> --ttl 15m [--level …] [--watch-pid <pid>\|auto] [--reason …]` | Named lease; re-acquiring an existing id renews it |
| `mooring lease renew <id> [--ttl …]` | Push the expiry forward |
| `mooring lease release <id> [--after 2m]` | End now, or shorten to a grace period |
| `mooring status [--json]` | Effective level, all leases, battery, thermal, lid, helper state |
| `mooring doctor` | Checks app, socket, helper approval, `pmset -g` SleepDisabled, CLI on PATH, Claude plugin installed |
| `mooring mcp` | Run the MCP server over stdio (2.5) |

**Conventions:** durations accept `90s`, `15m`, `2h`; `--json` on every command; exit codes 0 success, 1 usage error, 2 request refused by a guardrail (the reason is printed), 3 app unreachable. `--watch-pid auto` resolves the nearest ancestor process that isn't a shell, which for a hook is the Claude Code process.

**Other entry points** that map onto the same operations: a `mooring://on?level=lid&for=30m` URL scheme (for Raycast and Alfred), and App Intents for Shortcuts ("Keep Mac Awake", "Let Mac Sleep", "Get Awake Status"). The App Intents cover awake only; clipboard intents are excluded (Part 4).

### 2.3 Claude Code plugin

The plugin lives in `Integrations/claude-code-plugin/` and is installable from the repo as a plugin marketplace. It contains `hooks/hooks.json`, a skill, and an `.mcp.json` pointing at `mooring mcp`. Every hook command calls a small script, `${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook`, that reads the hook's JSON from stdin, takes `session_id`, and calls the CLI.

**Lease lifecycle for one session** (lease id `claude-<session_id>`):

| Hook event | Action | Why |
| --- | --- | --- |
| `UserPromptSubmit` | `acquire` with TTL 15 min, `--watch-pid auto`, reason from the first 60 characters of the prompt | Work starts when you send a prompt |
| `PostToolUse`, `PostToolBatch` | `renew` (async hook) | Heartbeat: an active agent keeps its lease fresh |
| `SubagentStart` / `SubagentStop` | `renew` | Long subagent runs count as work |
| `PermissionRequest`, `Notification` | Shorten to the "waiting for you" timeout (default 30 min) | Claude is blocked on you; don't burn battery for hours |
| `Stop` | `release --after 2m` | Grace period covers background shells and quick follow-ups |
| `StopFailure` | `release --after 2m` | An API error ends the turn the same way |
| `SessionEnd` | `release` now | Hard stop |

If Claude Code crashes, the watched PID exits and the lease ends at once; if the PID can't be resolved, the 15-minute TTL is the backstop. Hook leases use the `system` level. Lid mode for agents follows the approval setting in "Agent control and approvals" below; a per-project override is the env var `MOORING_AGENT_LEVEL=lid`.

**Hook rules** so Mooring can never break a Claude session:

- Every hook script exits 0, even on errors; failures go to Mooring's log, not to Claude.
- Renew hooks run with `"async": true`. Acquire and release are synchronous but time out at 2 s.
- If `mooring` isn't installed, the script is a no-op.
- Hook events and fields change over time; the plugin pins the events above, which match the current [hooks reference](https://code.claude.com/docs/en/hooks), and `mooring doctor` warns when the installed Claude Code reports an unknown version.

Sketch of `hooks/hooks.json`:

```json
{
  "description": "Keep the Mac awake while Claude works",
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook acquire", "timeout": 2 }] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook renew", "async": true }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook release --after 2m", "timeout": 2 }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook release", "timeout": 1 }] }]
  }
}
```

**Skill** (`skills/mooring/SKILL.md`): tells Claude that the Mac stays awake automatically while it works, and that for jobs which outlive the turn (a background build, a long download) it should wrap them in `mooring anchor --reason "…" -- <cmd>`. It also tells Claude never to disable Mooring or change its settings.

### Agent control and approvals

Agents act automatically by default; Settings → Awake → Agents lets the user make each area explicit.

| Setting | Options | Default |
| --- | --- | --- |
| Keep awake while agents work | **Automatic** (hooks anchor every session) · Explicit (hooks are no-ops; only `mooring anchor` or `keep_awake` calls count) | Automatic |
| Lid mode for agents | **Ask each time** · Always allow · Never | Ask each time |
| Window arrangement by agents | **Automatic** · Ask first · Off | Automatic |

**Ask each time** posts a notification: *"Claude Code wants to keep your Mac awake with the lid closed (full test suite). Allow once / Always allow / Deny."* The CLI call waits up to 60 s. On deny or timeout it exits with code 2 and prints the reason, and the lease falls back to `system` level, so the agent can say what happened instead of failing silently.

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

`mooring mcp` is a stdio MCP server that relays to the socket, so any MCP client can use it. Tools:

| Tool | Arguments | Notes |
| --- | --- | --- |
| `keep_awake` | `minutes` (1–240), `reason`, `level` (`system` or `lid`) | Lease id `mcp-<client>-<n>`; `lid` only if the user allowed agents lid mode |
| `release_awake` | `lease_id` (optional) | Only releases leases this client created |
| `awake_status` | none | Effective level, this client's leases, battery %, on AC, thermal state |
| `notify` | `title`, `body` | Posts a macOS notification ("Claude finished the refactor"); rate-limited to 1 per 30 s |

The MCP server never has clipboard tools; its window tools arrive with level 3 (3.4). It exposes no way to end leases owned by the menu or by other agents.

### 2.6 Policy for non-menu callers

| Rule | Value |
| --- | --- |
| Max single agent lease | 4 h, renewable while renewals keep arriving |
| Until turned off | Menu only |
| `lid` level for agents | Ask each time by default (see Agent control and approvals) |
| Max concurrent leases | 32 total; excess requests get exit code 2 |
| Reason text | Trimmed to 80 characters, control characters stripped before display |
| Guardrails (1.7) | Always win; the caller is told in the response |

Any process running as the user can take a lease; that's the same trust level as running `caffeinate`, and the menu always shows who holds one.

### 2.7 Notifications for walk-away use

Optional notifications when an agent lease ends ("Claude Code finished · 42 min") and when a guardrail suspends lid mode. With iPhone Mirroring or Focus sync these reach the phone; direct push (ntfy or Pushover URL) is a later add-on, off by default.

### 2.8 Level 2 acceptance criteria

- [ ] With the plugin installed, closing the lid mid-task keeps Claude working, and the Mac sleeps within 2 min of Claude stopping.
- [ ] Killing the Claude Code process ends its lease immediately.
- [ ] A Claude session waiting on a permission prompt lets the Mac sleep after 30 min.
- [ ] `mooring anchor -- sleep 60` keeps the Mac awake for 60 s and exits 0.
- [ ] Hooks add under 50 ms to a prompt submit and never surface an error in Claude Code.
- [ ] `mooring doctor` diagnoses a missing helper approval, a missing CLI and a missing plugin.

## Part 3: Window management (from Loop)

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
| `loop://` URL scheme | Scripting | Replaced by `mooring win` (3.4) |

**Mooring-only addition, later:** saved layouts ("Coding: terminal left two-thirds, browser right third"), which Loop's own comparison table lists as missing. A layout is a named list of (app bundle id, screen, action or frame) and is applied with one hotkey or `mooring win layout <name>`.

### 3.2 What gets removed from Loop

- Its own menu-bar icon, dock tile (`LoopDockTile`), About window and onboarding. Mooring's dropdown gains a Windows section instead.
- Its updater (`LoopUpdaterHelper`, ZIPFoundation). Mooring has one updater for the whole app (Appendix).
- Settings migration code for old Loop versions.
- Loop's settings window, rebuilt as the Windows settings group inside Mooring's settings. Loop's `Luminare` UI package is kept for those pages, since about 85 Loop files import it.

Dependencies kept: `Defaults` (shared with Maccy and level 1), `Scribe` (logging; replaced with Mooring's `os.Logger` if the port is small).

### 3.3 Permissions

Window management needs **Accessibility** (`AXIsProcessTrusted`). Mooring requests it only when the user turns on Windows, never at first launch, with a sheet explaining why and a button to open **Privacy & Security → Accessibility**. Levels 1 and 2 never need it. If permission is later revoked, Windows switches itself off and the icon shows the attention dot.

Maccy's paste action (level 4) needs the same permission, so granting it once covers both.

### 3.4 CLI and agent window control

An agent arranges windows from a plain request ("Chrome on the right half, iTerm bottom left, Slack top left") by reading the current windows, sending one plan, and reporting what landed. Mooring holds the Accessibility permission and does the matching and moving; the agent never needs Accessibility itself.

**The flow for one request:**

1. **Look.** `mooring win list --json` returns running apps and their windows (id, title, frame, screen, minimized, full screen) and every screen (id, name, visible frame, position).
2. **Plan.** The agent maps the request to one plan, all placements at once.
3. **Execute.** Mooring resolves each app and window, then applies every placement in one transaction through Loop's engine, optionally flashing Loop's preview overlay first.
4. **Report.** Mooring returns a status per placement; the agent tells the user anything that didn't land and can ask about ambiguous windows.

**CLI:**

| Command | Does |
| --- | --- |
| `mooring win list [--json]` | Apps, windows and screens as above |
| `mooring win arrange <app>=<region>[@screen] … [--launch] [--preview] [--json]` | One transaction, e.g. `mooring win arrange chrome=right-half iterm=bottom-left slack=top-left` |
| `mooring win arrange --plan <file or ->` | Same, with the full JSON plan |
| `mooring win <action> [--app <name>] [--screen …]` | One Loop action on one window |
| `mooring win undo` | Put every window moved by the last arrangement back |
| `mooring win layout save \| apply \| list \| delete <name>` | Saved layouts ("save this as coding") |
| `mooring win list-regions` | Every region name the planner accepts |

**Plan schema:**

```json
{
  "placements": [
    { "app": "chrome", "region": "right-half" },
    { "app": "iterm",  "region": "bottom-left", "screen": "main" },
    { "app": "slack",  "region": "top-left" },
    { "app": "code", "title": "mooring", "frame": { "x": 0, "y": 0, "w": 0.6, "h": 1 } }
  ],
  "launch": false,
  "preview": false
}
```

- **`app`** is matched against running apps' names and bundle ids, case-insensitive and fuzzy ("iterm" → iTerm2 `com.googlecode.iterm2`, "code" → Visual Studio Code). Ties are reported as ambiguous, never guessed.
- **`region`** is any Loop action name (halves, quarters, thirds, two-thirds, maximize, almost-maximize, centre). **`frame`** gives fractions of the screen's visible area for anything else.
- **`screen`** is `main`, `left`, `right`, or an index; default is the screen the window is on.
- **`title`** picks one window when an app has several; default is the app's frontmost window.
- Minimized windows are restored. Apps that aren't running are launched only when `launch` is true.

**Result per placement:** `ok` (with the final frame), `partial` (the app enforces a minimum size; final frame given), `ambiguous` (candidate windows listed), `not_running`, `not_found`, or `failed` (reason). The CLI exits 0 only when every placement is `ok`.

**MCP tools** (same schema as the CLI): `list_windows`, `arrange_windows(placements, launch, preview)`, `undo_arrangement`, `save_layout(name)`, `apply_layout(name)`.

**Skill guidance:** list windows before arranging; send one plan rather than one call per window; report every placement that isn't `ok`; offer `mooring win undo` if the user doesn't like the result.

**Control mode:** agents arrange windows automatically by default. "Ask first" shows a notification summarising the plan ("Claude Code wants to arrange 3 windows") with Allow; "Off" makes the window commands and tools return an error the agent can relay (see Agent control and approvals in Part 2).

Example exchange:

```
You:    Put Chrome on the right half, iTerm bottom left and Slack top left.
Claude: mooring win list --json
        mooring win arrange chrome=right-half iterm=bottom-left slack=top-left --json
        → chrome ok · iterm ok (was minimized, restored) · slack ok
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
- [ ] The Chrome / iTerm / Slack request lands in one `mooring win arrange` call, and `mooring win undo` restores the previous layout
- [ ] A failing private-API call hides the dependent feature instead of crashing.
- [ ] The Shortcuts page detects a clash between the Windows trigger and the clipboard hotkey.

## Part 4: Clipboard history (from Maccy, never exposed to agents)

Level 4 vendors Maccy as a `ClipKit` package, off by default, with the same storage and privacy behaviour as Maccy (no added encryption, decided 2026-09-29). Agents get no clipboard API: no CLI command, MCP tool, App Intent, URL route or AppleScript returns history.

### 4.1 Features carried over

| Feature | Maccy behaviour kept |
| --- | --- |
| Popup | ⇧⌘C (configurable) opens the dropdown straight to the Clipboard section, with the search field focused (see UX) |
| Search | Type to filter; exact, fuzzy and regex modes with match highlighting |
| Copy / paste | Return copies; ⌥Return pastes; ⌥⇧Return pastes without formatting; ⌘/⌥ + number for the first items |
| Pins | ⌥P pins an item to the top with a permanent shortcut |
| Content types | Text, rich text, images, files, colours, with the source app's icon |
| Delete and clear | ⌥⌫ deletes one; "Clear" removes unpinned; Clear with ⌥ removes all |
| Pause | "Pause Recording" and "Ignore Next Copy" as rows in the Clipboard section (Maccy uses ⌥-click on its own icon for these) |
| History size | Default 200 items, adjustable |

### 4.2 What gets removed from Maccy

- **App Intents** (`Intents/Get.swift`, `Select.swift`, `Delete.swift`, `Clear.swift`). "Get" and "Select" would let Shortcuts, and anything that can run `shortcuts run`, read the history. All four are deleted, not hidden.
- Its menu-bar icon, updater (Sparkle moves up to the app level), App Store review prompt and About window.
- The `defaults write … ignoreEvents` switch, replaced by the Pause menu item.

Maccy's SwiftData models (`HistoryItem`, `HistoryItemContent`) are kept; that's why the whole app needs macOS 14.

### 4.3 The agent wall

| Path an agent could use | How it's closed |
| --- | --- |
| `mooring` CLI and socket | No clipboard operations exist in the IPC protocol; unknown ops are rejected |
| MCP server | No clipboard tools; the server's tool list is fixed at build time |
| Shortcuts / App Intents | Maccy's intents deleted (4.2) |
| URL scheme | `mooring://` has no clipboard routes |
| AppleScript | No scripting dictionary (`NSAppleScriptEnabled` = NO) |
| Reading the database file | File permissions only; see the known limitation in 4.4 |
| Reading the live pasteboard | Out of Mooring's control; any app can read the *current* clipboard, as today |

The last row is worth saying plainly in the README: Mooring protects the history, not whatever you most recently copied.

### 4.4 Storage

- The store is its own SwiftData container at `~/Library/Application Support/Mooring/Clipboard/`, separate from settings and leases, directory mode `0700`. Contents are stored as Maccy stores them, unencrypted.
- The store is excluded from Time Machine and iCloud backups (`isExcludedFromBackup`).
- Retention matches Maccy: keep the last 200 items by default. "Clear history on quit" is an optional setting.

**Known limitation.** Maccy runs sandboxed, so macOS guards its history file with an "access data from other apps" prompt. Mooring ships unsandboxed, like Loop and Awayke, so any process running as you, including an agent with shell access, can read the history file without a prompt. Closing that gap would take either encryption or moving ClipKit into a separate sandboxed helper app; revisit if it matters.

### 4.5 What's never recorded

- Pasteboard types marked confidential or temporary: `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType` (always, as in Maccy).
- Maccy's default ignore list: 1Password, KeeWeb, TypeIt4Me and similar types, editable.
- Copies made while Secure Keyboard Entry is active (`IsSecureEventInputEnabled()`), which covers most password fields.
- Apps on an ignore list; defaults include the major password managers and Keychain Access.
- Universal Clipboard copies from other devices, optionally (`com.apple.is-remote-clipboard`, off by default).

### 4.6 Permissions

Recording history needs no permission. Auto-paste needs **Accessibility**, the same grant level 3 uses. Without it, selecting an item copies it and the user pastes with ⌘V.

### 4.7 Level 4 acceptance criteria

- [ ] With Clipboard off, nothing is recorded and no store is created.
- [ ] A password copied from 1Password never appears in history.
- [ ] No CLI command, MCP tool, App Intent, URL or AppleScript call returns history contents.
- [ ] Popup opens in under 100 ms with 200 items, and search filters as you type.

## Appendix

### A. Distribution and updates

- **No paid Apple account (decided 2026-09-29).** Mooring ships on GitHub only, not the App Store, and without Developer ID signing or notarization. Two install paths:
  1. **Build from source (recommended for developers):** `git clone` then `make install`, which builds with Xcode using the developer's own free Apple ID (personal team). Apps built locally aren't quarantined, so Gatekeeper never warns, and the signature is stable across rebuilds.
  2. **Prebuilt download:** `Mooring.zip` on GitHub Releases, signed with a project self-signed certificate. On first open macOS blocks it; the README shows the fix: System Settings → Privacy & Security → Open Anyway, or `xattr -dr com.apple.quarantine /Applications/Mooring.app`.
- **Consequences of skipping Developer ID:**
  - Official Homebrew casks now reject apps that fail Gatekeeper (Chai is being removed for this), so Homebrew means a project tap only.
  - The helper's caller check (1.5) pins the signing certificate's hash instead of a Team ID.
  - Accessibility grants (levels 3 and 4) are tied to the signature, so the signing identity must stay the same across updates or users re-grant after every update.
- **Spike before level 1 build-out:** confirm that `SMAppService.daemon` registers and runs a helper signed with a self-signed or personal-team certificate on macOS 14, 15, 26 and 27 (the owner's M4 Pro runs 27). If it doesn't, lid mode falls back to a one-time `sudo mooring install-helper` that installs a launchd daemon the classic way.
- **Updates:** Sparkle with an EdDSA-signed appcast on GitHub Pages; Sparkle's own signature check works without Developer ID. The update check is the only network access and is opt-in on first launch. Build-from-source users update with `git pull && make install`.
- **Uninstall:** Settings → Advanced → "Uninstall…" restores sleep, unregisters the helper and login item, removes the CLI symlink, and offers to delete clipboard history.

### B. Open questions

Decided 2026-09-29: name **Mooring**, repo `github.com/EidanErlich/mooring`; GPL-3.0; plain-snapshot vendoring with provenance docs; anchor icon (outline off, filled on); agents act automatically by default, lid mode for agents asks each time; lid mode on battery behind an explicit opt-in; no clipboard encryption beyond Maccy's; development is staged (Build brief below).

- [ ] Is the 2-minute grace after `Stop` long enough for background shells Claude starts? Measure on real sessions in stage 2.
- [ ] Keep Loop's `Luminare` settings UI, or rebuild the Windows pages in plain SwiftUI for consistency? Decide at the start of stage 3.
- [ ] Does `SMAppService.daemon` accept a personal-team-signed helper on macOS 27? Answered by the stage 1 spike.

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
| Repo | `github.com/EidanErlich/mooring` (public) |
| License | GPL-3.0-only; upstream MIT notices kept |
| App name / CLI | Mooring / `mooring` |
| Bundle IDs | App `dev.mooring.app`; helper `dev.mooring.helper` (also its Mach service name); CLI `dev.mooring.cli` |
| Dev and test machine | MacBook Pro, Apple M4 Pro, macOS 27 |
| Deployment target | macOS 14 |
| Toolchain | Current Xcode release for macOS 27; Swift 6 language mode with strict concurrency |
| Signing | Free Apple ID personal team (Apple Development certificate); no Developer ID, no notarization |

### Repository setup

- **Project generation:** XcodeGen from `project.yml`. The generated `Mooring.xcodeproj` is gitignored, so agents never hand-edit a `.pbxproj`.
- **Targets:** `Mooring` (app); `MooringHelper` (command-line tool embedded at `Contents/MacOS/dev.mooring.helper`, launchd plist at `Contents/Library/LaunchDaemons/dev.mooring.helper.plist`); `mooring` CLI (embedded at `Contents/MacOS/mooring`); local packages in `Packages/`; unit test targets per package.
- **Signing config:** `Config/Local.xcconfig` (gitignored) holds `DEVELOPMENT_TEAM`; `Config/Local.xcconfig.example` is committed. A build-phase script writes the helper's allowed-client requirement from the app's signing certificate hash, so no team ID is hardcoded.
- **Dependencies (Swift Package Manager, pinned):** Defaults, KeyboardShortcuts, Sauce (stage 1–4), Sparkle (stage 5), Luminare and Scribe only if stage 3 keeps them.
- **CI:** GitHub Actions on a macOS runner: bootstrap, unsigned build (`CODE_SIGNING_ALLOWED=NO`), unit tests. Nothing that needs the helper, lid or permissions runs in CI.

```
make bootstrap    # brew install xcodegen swiftlint; xcodegen generate
make build        # Debug build of the Mooring scheme
make test         # all unit test targets
make install      # Release build to /Applications, CLI symlink at ~/.local/bin/mooring
make reset-sleep  # sudo pmset -a disablesleep 0 (manual safety valve)
make uninstall    # restore sleep, unregister helper, remove app and symlink
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
| `Awayke/AutoOffPolicy.swift` | `Packages/AwakeKit/Guardrails/AutoOffPolicy.swift` | Add thermal input and the battery opt-in |
| `Awayke/LidSessionTracker.swift` | `Packages/AwakeKit/LidSessionTracker.swift` | None |
| `Awayke/DisplayWakeKeeper.swift` | `Packages/AwakeKit/Assertions.swift` | Merge with a system-sleep assertion |
| `Awayke/HelperManager.swift` | `App/Helper/HelperClient.swift` | Add heartbeat and status read |
| `AwaykeHelper/main.swift`, `AwaykeHelperProtocol.swift`, both plists | `Helper/` | Add caller check, watchdog, heartbeat (1.5, 1.6) |
| `Awayke/PowerManager.swift`, `AutoOffTimer.swift`, `.github/workflows/release.yml` | Reference only | osascript fallback dropped; timers replaced by lease expiry; signing steps removed |

**Chai (stage 1):** reimplemented, not copied. Reference `ActivationSpecs.swift` (durations), `PowerAssertion.swift` (assertion calls) and `ChaiApp.swift` (wake handling, launch at login via `SMAppService.mainApp`).

**Maccy, early (stage 1):** copy `FloatingPanel.swift` into `App/UI/` for the dropdown panel.

**Loop → WindowKit (stage 3)**

- Take: `Window Management/`, `Window Action Indicators/` (radial menu, preview window), `Core/` except `URLCommandHandler.swift`, `Utilities/`, `Extensions/`, `Private APIs/`, `Stashing/` (compiled but switched off), and the settings pages under `Settings Window/Settings/` and `Settings Window/Theming/`.
- Leave: `Updater/`, `LoopUpdaterHelper/`, `LoopDockTile/`, `Migration/`, `Icon/`, `Resources/AppIcon-*`, `Core/URLCommandHandler.swift` (replaced by `mooring win`).

**Maccy → ClipKit (stage 4)**

- Take: `Models/`, `Observables/`, `Views/`, `Extensions/`, `Storage.swift`, `Storage.xcdatamodeld`, `Clipboard.swift`, `Search.swift`, `Sorter.swift`, `HighlightMatch.swift`, `HistoryItemAction.swift`, `PasteStack.swift`, `KeyChord.swift`, `KeyShortcut.swift`, `KeyboardLayout.swift`, `Accessibility.swift`, `ApplicationImage.swift`, `ApplicationImageCache.swift`, `ColorImage.swift`, `Throttler.swift`.
- Leave: `Intents/`, `SoftwareUpdater.swift`, `AppStoreReview.swift`, `About.swift`, `MenuIcon.swift`, `Settings/` (rebuilt as Clipboard pages), `AppDelegate.swift` and `MaccyApp.swift` (reference only).
- Change the store path to `~/Library/Application Support/Mooring/Clipboard/`.

### Menu-bar icon

- An anchor: outline when off, filled when on; badges and the attention dot as in the UX section.
- If SF Symbols on macOS 27 includes an anchor, use it and its `.fill` variant. Otherwise draw an original vector: `MenubarAnchor` and `MenubarAnchorFill` in `Assets.xcassets`, 18 × 18 pt, rendered as template images.
- App icon: a placeholder anchor on a rounded square until a designed icon exists.

### Engineering decisions (authoritative)

If anything earlier in this spec conflicts with this subsection, this subsection wins.

**Languages and packages**

- First-party code (App, Helper, CLI, the `AwakeKit` and `MooringIPC` targets) uses Swift 6 with strict concurrency.
- Swift language mode is set per SwiftPM target, not per file, so vendored code lives in its own targets set to `swiftLanguageModes: [.v5]`: `AwaykeMonitors` (inside the AwakeKit package: `LidMonitor`, `BatteryMonitor`, `LidSessionTracker`, `AutoOffPolicy`), `WindowKit`, `ClipKit`. `AwakeKit` depends on `AwaykeMonitors`. Minimal edits to compile (`@unchecked Sendable`, `nonisolated(unsafe)`) are allowed and logged in `UPSTREAM.md`.
- SwiftPM layout is standard: `Packages/<Package>/Package.swift`, `Sources/<Target>/`, `Tests/<Target>Tests/`. The Awayke file-map destinations therefore mean `Packages/AwakeKit/Sources/AwaykeMonitors/<File>.swift` for the four files above and `Packages/AwakeKit/Sources/AwakeKit/` for the rest.
- Tests use Swift Testing. Awayke's custom-runner tests are ported to it. `make test` runs `swift test` in each package plus `xcodebuild test` for the app scheme. Stage 0 adds one trivial test per package so the command passes.
- The app's `Info.plist` sets `LSUIElement = YES` (no Dock icon).
- SwiftLint runs via `make lint` and as a non-blocking CI step: default rules, `line_length` warning at 140, vendored targets excluded.
- CI uses the newest macOS runner image GitHub offers (at least `macos-15`) with its default Xcode; the macOS 14 deployment target keeps that compatible.

**Helper and signing**

- `Helper/Shared/MooringHelperProtocol.swift` is compiled into both the app and the helper. `MooringIPC` holds only the socket format, so the helper has no dependencies.
- `scripts/write-helper-requirement.sh` runs as a build phase: it reads the SHA-1 of the certificate signing the app and writes `identifier "dev.mooring.app" and certificate leaf = H"<sha1>"` into the helper's `SMAuthorizedClients` and into a generated Swift constant used by `setConnectionCodeSigningRequirement`. In CI (`CODE_SIGNING_ALLOWED=NO`) it writes a placeholder and the build defines `MOORING_UNSIGNED`, which only the CI build uses.
- **Spike fallback (stage 1a, only if `SMAppService` registration fails):** stage 1a also builds a minimal `mooring install-helper` that copies the helper to `/Library/PrivilegedHelperTools/dev.mooring.helper`, writes `/Library/LaunchDaemons/dev.mooring.helper.plist` (same label and Mach service), and runs `launchctl bootstrap system` on it, under `sudo`.
- **Stage 1a debug control:** in Debug builds only, right-clicking the icon shows a native `NSMenu` with "Disable lid sleep", "Enable lid sleep" and "Read SleepDisabled". Stage 1b replaces it with the dropdown panel.

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
  var agentKeepAwake: AgentMode = .automatic                // .automatic, .explicit
  var agentLid: AgentLidMode = .askEachTime                 // .askEachTime, .alwaysAllow, .never
  var agentWindows: AgentWindowMode = .automatic            // .automatic, .askFirst, .off
}
```

- **Suspensions** are engine state; leases are never modified by guardrails. They show as the status line and the attention dot. Thermal compares `ThermalState.rawValue` (`.serious` or worse suspends lid; back to `.nominal` resumes). Low-battery-all resumes when on AC. Low-battery-lid resumes on AC at threshold + 5%.
- **Guardrail settings:** lid threshold 20% and all-leases threshold 10% by default; each can be set to Off. There is no one-off override beyond these settings and the lid-on-battery opt-in.
- **Lease ids:** `menu`, `lid-session` (until I open the lid), `app-<pid>` (while an app runs), `cli` (`mooring on`, one shared id), `anchor-<pid>` (`mooring anchor`), `claude-<session_id>`, `mcp-<client>-<n>`. There is no `timer` id; durations are `expiresAt` on the `menu` lease.
- **Naming:** the UI says "Until turned off" (never "Forever"); code uses `expiresAt == nil`. The wake setting is named "End my session after the Mac sleeps" (default off); it ends the `menu` lease whatever its duration and never touches agent leases.
- `leases.json` is written with mode `0600`.

**UI details for stage 1b**

- **Clicks:** set `statusItem.button.sendAction(on: [.leftMouseUp, .rightMouseUp])` and branch on `NSApp.currentEvent`; Control-click counts as right click.
- **Dropdown panel:** adapted from Maccy's `FloatingPanel.swift`. Remove its `AppState`, `Popup`, `PopupPosition`, preview and Maccy `Defaults` keys. Anchor it under the status item; width 320 pt; height fits content up to 70% of the screen; closes on outside click or Esc.
- **"While an app runs…"** lists `NSWorkspace.shared.runningApplications` with `activationPolicy == .regular`, with icons.
- **Settings window:** plain SwiftUI `NavigationSplitView` with the sidebar from the UX section. Items from 1.9 map to: helper, AC requirement, thresholds, thermal → Awake › Lid & Battery; notifications → General; logs, diagnostics, uninstall → Mooring › Advanced. Luminare is used only for the Windows pages in stage 3.
- **Defaults:** global On/Off hotkey none; ⇧⌘C not registered until stage 4. Notification permission is requested the first time lid mode or a guardrail notification is needed.
- **Icon:** check the SF Symbols app on macOS 27 for an anchor symbol and its `.fill` variant; if there is none, ship custom template assets in stage 0. Badges are small symbols composited at the bottom right: `laptopcomputer` (lid mode), `battery.25` (on battery), a 5 pt dot (attention).

**Stage 2 details**

- **Socket protocol:** request `{"v":1,"id":"<uuid>","op":"acquire|renew|release|status|approve.wait|win.list|win.arrange|win.undo|win.layout","args":{…}}`; response `{"v":1,"id":"…","ok":true,"result":{…}}` or `{"v":1,"id":"…","ok":false,"error":{"code":"bad_request|guardrail|denied|not_found|internal","message":"…"}}`. Exit codes: `bad_request` → 1, `guardrail` or `denied` → 2, app unreachable → 3, `internal` → 4. An Ask-each-time approval holds the connection open for up to 60 s.
- **Hooks:** `hooks.json` registers every event in the 2.3 table (`UserPromptSubmit`, `PostToolUse`, `PostToolBatch`, `SubagentStart`, `SubagentStop`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SessionEnd`). Renewals are `async`; the others time out at 2 s. Hooks never launch the app: if the socket is missing, `mooring-hook` exits 0 immediately, which keeps hook cost under 50 ms. Auto-launch applies only to interactive CLI use.
- **MCP:** runs inside the CLI (`mooring mcp`); there is no separate server package. The client id is the slugified `clientInfo.name` from the MCP `initialize` request.
- The `mooring://` URL scheme and the awake App Intents ship in stage 2a.
- `mooring doctor` records the Claude Code version the plugin was tested with in `plugin.json` and warns when `claude --version` reports a different major version.

**Stage 3 additions to the Loop file map**

- Also take `Shared/`, `Core/Multitouch/` (needed for gestures), `Settings Window/Loop/` (Advanced and Excluded Apps pages; About is dropped), and adapt `SettingsContentView.swift`, `SettingsTab.swift` and `SettingsWindowManager.swift` into the Windows settings group. Use `App/` as wiring reference only.
- Dependencies: Luminare (imported by about 85 Loop files, so it stays), Scribe, Defaults, Subsurface.
- Undo keeps the last 10 arrangements in memory (window id → previous frame); it is lost on quit.

**Stage 4 additions to the Maccy file map**

- Also take `GlobalHotKey.swift`, `ItemsProtocol.swift`, `Notifier.swift`, `PinsPosition.swift`, `PopupPosition.swift`, `SearchVisibility.swift`, `Selection.swift`, `VoiceOver.swift`, `Sounds/`, and `History.xcdatamodeld`. `Intents/` has six files; all are left out.
- Dependencies: Defaults, KeyboardShortcuts, Sauce, swift-log, SwiftHEXColors, Fuse (fuzzy search). Maccy's Settings and LaunchAtLogin packages are not needed.
- Store file: `~/Library/Application Support/Mooring/Clipboard/Storage.sqlite`.
- Default ignored apps (bundle ids): `com.1password.1password`, `com.agilebits.onepassword7`, `com.bitwarden.desktop`, `com.apple.keychainaccess`, `com.apple.Passwords`, `org.keepassxc.keepassxc`.
- Skipping copies while Secure Keyboard Entry is on (`IsSecureEventInputEnabled()`) is new code, not in Maccy.

**Stage 5**

- Sparkle appcast at `https://eidanerlich.github.io/mooring/appcast.xml`. The EdDSA private key stays in the owner's Keychain, never in the repo or CI; releases are signed on the owner's Mac.
- Keep the same personal-team signing certificate across releases so Accessibility grants survive updates; if it ever changes, the release notes tell users to re-grant.

**Gates between levels** (the roadmap diagram in the Appendix): a level is done only when its stages' owner checkpoints below have passed.

### Stages

Each stage is one branch and one pull request titled `Stage N: …`, and ends at its owner checkpoint.

| Stage | Builds | Agent verifies | Owner checkpoint |
| --- | --- | --- | --- |
| 0 Scaffold | Repo, `project.yml`, Makefile, CI, LICENSE, THIRD\_PARTY, README; an empty menu-bar app with the outline anchor | `make bootstrap build test` passes; CI green | Launches the app and sees the icon |
| 1a Helper spike | Minimal helper: register, set and read `disablesleep`, caller check; a debug menu item to flip it | `pmset -g \| grep SleepDisabled` flips between 1 and 0 | Approves the helper in System Settings. If registration fails, switch to the `sudo mooring install-helper` fallback |
| 1b Awake engine | Leases, reconciler, assertions, On defaults, the dropdown panel with the Awake section, General and Awake settings | Unit tests; `pmset -g assertions` shows Mooring's assertion; left click toggles | Uses it for a day |
| 1c Lid and guardrails | Lid level, watchdog, heartbeat, launch reset, battery and thermal guardrails, battery opt-in sheet | Scripted `kill -9` of the app returns SleepDisabled to 0 within 15 s | Closes the lid for 10 min with `ping -i 5 1.1.1.1 > ~/lidtest.log` running, on AC and on battery; checks the log has no gap |
| 2a IPC and CLI | Socket, all `mooring` commands in 2.2, `doctor`, CLI install | `mooring anchor -- sleep 20` shows in `mooring status --json`; exit codes match 2.2 | None |
| 2b Claude Code plugin | Hooks, skill, installable marketplace | Sample hook JSON piped to `mooring-hook` acquires, renews and releases a lease | Runs a real Claude Code session with the lid closed |
| 2c Approvals and MCP | Allow once / Always / Deny notifications; `mooring mcp` awake tools | MCP calls from a test client; the deny path exits 2 | Clicks each notification button |
| 3a WindowKit | Vendored Loop, radial menu, keybinds, Windows settings, Accessibility flow | With Windows off, no Accessibility prompt and WindowKit not loaded; frame-resolver unit tests | Grants Accessibility; tries the radial menu and keybinds |
| 3b Agent windows | `mooring win list / arrange / undo / layout`, MCP window tools, skill update | Arranging three TextEdit windows returns `ok` frames; `undo` restores them | Asks Claude for the Chrome / iTerm / Slack layout |
| 4 ClipKit | Vendored Maccy in the Clipboard section, ⇧⌘C, ignore rules, retention | Unit tests; a test fails the build if any IPC op, MCP tool, intent or URL route touches ClipKit | Copies from 1Password and confirms it isn't recorded |
| 5 Release | Sparkle appcast, GitHub Release zip, Homebrew tap `EidanErlich/homebrew-tap`, README install docs | Clean install on a second macOS user account | Tags v0.1 |

### Rules for agents

- Build only the assigned stage. At the end, list exactly what the owner must do for the checkpoint.
- Never leave sleep disabled: every test that touches lid mode sets `disablesleep 0` in teardown. `make reset-sleep` is the manual escape hatch.
- Only the helper runs `pmset`. The app and CLI never call it directly.
- Keep the helper under 250 lines with no dependencies.
- No network access in app code except Sparkle, from stage 5.
- Don't claim behaviour you couldn't observe (lid, battery, notifications, permission prompts); mark it "needs owner check".
- Swift 6 strict concurrency; `@MainActor` for UI and `AwakeEngine`; `os.Logger` with subsystem `dev.mooring`.
- Changes offered back to Loop must follow Loop's `AI_POLICY.md`.

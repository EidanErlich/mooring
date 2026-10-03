# Stage 3a: WindowKit (Loop inside Mooring)

Oct 3, 2026 · Eidan Erlich · Status: design approved in conversation; spec awaiting owner review

## Goal

Loop's window manager runs inside Mooring as **WindowKit**, behind the same menu-bar icon. It includes the radial menu, preview, about 50 keyboard actions, cycles, custom frames and drag-to-edge snapping.

It is **off by default**. Mooring asks for Accessibility only when you turn Windows on, and with Windows off no WindowKit code runs.

This is the first half of SPEC.md stage 3. **3b**, agent windows (`mooring win list / arrange / undo / layout`, MCP window tools and a skill update), gets its own spec and builds on this one.

## Owner decisions (2026-10-03)

| Question | Decision |
| --- | --- |
| How much of Loop | **All of it, as SPEC.md describes, plus the agent layer in 3b.** Radial menu, keybinds, cycles, snap by drag, preview and theming. |
| Windows settings UI | **Keep Luminare.** Loop's own pages, as the Windows group in Mooring's Settings. |
| How stage 3 is split | **Two parts:** 3a WindowKit (this spec), then 3b Agent windows. |
| Existing Loop install | **None on this Mac.** No settings import. |

## Vendoring

- **The snapshot** is Loop at `0ac6d834fb2cb542e62748021a88ee0f6a728fd7` (2026-09-29), copied as plain files with no git history, following the Build brief's vendoring rules:
  - every copied file keeps its original header;
  - every changed file gains a first line, `// Adapted from Loop@0ac6d83: <original path>`;
  - `THIRD_PARTY/Loop/UPSTREAM.md` lists every file taken (old path → new path) and every modification.
- **The package** is `Packages/WindowKit`, a local Swift package next to AwakeKit and MooringIPC.
  - Its dependencies are pinned to **exact revisions**, because Loop tracks them on `main` with no `Package.resolved`: Luminare, Scribe, Subsurface and Defaults. Defaults is already a dependency, so WindowKit uses the same version.
  - The chosen revisions, and why, go in `UPSTREAM.md`.
- **Take** the SPEC.md file map plus its stage 3 additions:
  - `Window Management/`;
  - `Window Action Indicators/` (radial menu, preview);
  - `Core/` except `URLCommandHandler.swift`, plus `Core/Multitouch/`;
  - `Utilities/`, `Extensions/` and `Private APIs/`;
  - `Stashing/` (compiled, switched off);
  - `Shared/` and `Accent Color/`;
  - the settings pages under `Settings Window/Settings/`, `Settings Window/Theming/` and `Settings Window/Loop/` (Advanced, Excluded Apps);
  - Loop's unit tests, where they exist.
- **Leave:**
  - `Updater/`, `LoopUpdaterHelper/`, `LoopDockTile/`, `Migration/`, `Icon/`;
  - `Resources/AppIcon-*`, `Core/URLCommandHandler.swift`;
  - the About page, onboarding, and Loop's own status item;
  - the `Updater` and `IconManager` calls in `LoopManager`.

  `App/` is wiring reference only.
- **Swift language mode:** WindowKit compiles in Swift 6 mode if the port is small. Otherwise the package sets Swift 5 language mode, so Loop's code stays as upstream wrote it. The app and the other packages stay Swift 6. The choice is recorded in `UPSTREAM.md`.
- **License:** Loop is GPL-3.0, and the monorepo is already GPL-3.0-only. The README's Credits section already links Loop; check it.

## Off means off

- **One owner:** a Mooring-side **`WindowsController`** (`App/Windows/`) owns WindowKit's lifecycle.
  - **While Windows is off**, it never creates Loop's managers, event monitors, event taps, Multitouch listeners or Accessibility calls, and nothing in WindowKit runs at launch.
  - **Turning on** starts them; **turning off** stops and releases them.
- **Settings key:** `windowsEnabled: Bool = false`, under Mooring's settings, with a fallback when decoding older settings.
- **Where Loop's settings live:** Loop's own `Defaults` keys stay in a separate `UserDefaults` suite (`dev.mooring.windows`), so they can't collide with Mooring's keys.
- **Test seams:** WindowKit's start and stop go through a protocol, so tests can show that none of WindowKit's entry points are called while Windows is off, at launch or in steady state.

## Private APIs

- **Capability checks:** every SkyLight path (`@_silgen_name`, runtime symbol loading) sits behind a check, run once when Windows starts.
- **A failed check fails closed:** the dependent feature hides itself (menu item, setting or action), and the failure is logged once through `os.Logger` with the category `windows`. It never crashes.
- **Stash and focus switching** stay hidden in 3a, as SPEC.md 3.1 says.

## Turning Windows on

- **Where:**
  - the dropdown's **Windows ›** submenu, which shows a single **Turn On…** item while Windows is off;
  - Settings → Windows → Behavior, through the **Window Manager** toggle.
- **If Accessibility is granted** (`AXIsProcessTrusted()`), Windows turns on immediately.
- **If it isn't:**
  - A sheet explains: "Mooring moves and resizes other apps' windows. macOS calls this Accessibility." It has **Open Privacy & Security**, which opens the Accessibility pane, and **Cancel**.
  - Mooring polls trust every 2 s for up to 5 minutes while the sheet is open, or while the request is pending. When trust arrives, Windows switches on by itself, with no relaunch.
  - Mooring never asks at launch, and levels 1 and 2 never need it.
- **If trust is revoked while on** (checked every 5 s while Windows is on):
  - Windows switches off;
  - `windowsEnabled` stays true, recording that you want it;
  - the icon shows the orange attention pill with the new reason, **"Windows needs Accessibility"**;
  - the submenu shows **Turn On…** again.

  When trust comes back, Windows resumes on its own and the pill clears.

## Dropdown: Windows ›

While Windows is on, the submenu holds, in order:
1. **Left half, Right half, Maximize, Centre, Next screen**, each showing its current Loop shortcut;
2. **More Actions ›**, with every other Loop action, grouped as Loop groups them;
3. a separator;
4. a **Window Manager** on/off switch row.

Actions apply to the frontmost window of the app that was active before the menu opened.

Saved layouts arrive with 3b, and the submenu has no placeholder for them.

## Settings → Windows

A new sidebar group with Loop's Luminare pages, hosted in Mooring's Settings window:

| Page | Contents |
| --- | --- |
| Behavior | Loop's Behavior and Advanced settings, plus the Window Manager on/off toggle |
| Keybinds | Loop's defaults, including its trigger key |
| Gestures | Loop's Multitouch gestures |
| Radial Menu | Loop's Radial Menu and Accent Color settings |
| Preview | Loop's Preview settings |
| Excluded Apps | Loop's Excluded Apps |

- **Dropped:** Loop's Icon page and About page.
- **Pages while Windows is off:** each one shows a banner with "Windows is off" and **Turn On…**. Editing is still allowed; settings take effect when Windows starts.
- **Hosting:** Luminare views are hosted inside Mooring's `NavigationSplitView` detail area. If Luminare needs its own window chrome, the Windows group opens Loop's settings window instead, titled "Mooring: Windows", and the sidebar item opens that. The plan records which.

## General → Shortcuts

- **A new page** lists every global shortcut Mooring has: the awake on/off shortcut (none by default), Windows' trigger key, and every Windows keybind.
- **Conflicts:**
  - Two Mooring shortcuts with the same chord show a ⚠ on both rows: "Also used by <other>".
  - A chord that matches a detectable system shortcut shows "Used by macOS: <name>". Detection reads the symbolic hotkeys from `com.apple.symbolichotkeys`, the ones that are enabled.
- **A link** points to Loop's README advice about remapping Caps Lock. Mooring never remaps it.
- **Editing:** the page lists shortcuts and flags conflicts. Shortcuts are edited where they live: Windows → Keybinds, and Awake for the on/off shortcut.
- **Stage 4** adds the clipboard shortcut to this page.

## Version and docs

- The stage ships as **0.0.4**: `MARKETING_VERSION`. The plugin is unchanged.
- **SPEC.md:**
  - Part 3 marks 3a as built;
  - Open question B (Luminare) is answered "Keep";
  - the stage table's 3a row is updated;
  - the file map records what was actually taken;
  - Engineering decisions gain the pinned revisions, the Swift language mode, the `dev.mooring.windows` suite and the capability checks.
- **README:** Credits (Loop), and a short "Windows" section.

## Components

| Piece | Where | Does |
| --- | --- | --- |
| WindowKit | `Packages/WindowKit` | Vendored Loop, trimmed. Exposes a small start/stop surface and the action list. |
| `WindowsController` | `App/Windows/` | Lifecycle, Accessibility polling, revoke handling, the attention reason. |
| `AccessibilityTrust` | `App/Windows/` | A protocol over `AXIsProcessTrusted` and opening the pane, injected in tests. |
| Capability checks | WindowKit | One check per private-API feature, run at start, failing closed. |
| Windows submenu | `App/UI/` | Built the same way as the Awake submenu. |
| Settings group | `App/Settings/` | Hosts the Luminare pages, plus the off banner. |
| Shortcuts page | `App/Settings/` | Lists shortcuts, with `ShortcutConflicts` (pure) and `SystemHotkeys` (reads the symbolic hotkeys). |

## Testing

- **Off means off:**
  - launching with `windowsEnabled = false` creates no WindowKit manager and calls no WindowKit entry point;
  - the trust probe is never called at launch;
  - toggling on, then off, releases everything.
- **Turning on:**
  - trusted → on;
  - untrusted → sheet, then trust arrives → on;
  - the 5-minute timeout → stays off.
- **Revoked:** while on, trust goes false → off, the pill reason appears, and `windowsEnabled` stays true; trust returns → on and the pill clears.
- **Frame maths:**
  - each 3a action's target frame, for one screen and two screens of different sizes (halves, quarters, thirds, two-thirds, maximize, almost maximize, centre, grow and shrink, next and previous screen);
  - cycles step through and wrap;
  - Loop's own tests, copied, pass.
- **Capability checks:** a forced failure hides the dependent feature and doesn't crash.
- **Shortcuts:** duplicate chords are flagged on both rows; a chord matching an enabled system hotkey is flagged; disabled system hotkeys aren't.
- **Dropdown:** Windows off shows only **Turn On…**; Windows on shows the five actions with their chords, More Actions and the switch.
- **CI:** one CI run's time is recorded in the plan's ledger. If it grows by more than about 50%, cache SwiftPM packages in the workflow.

## Owner check

1. Use Mooring with Windows off. No Accessibility prompt ever appears.
2. Choose **Windows › Turn On…**, then grant Accessibility in System Settings. Windows switches on by itself.
3. Try:
   - the radial menu (trigger key);
   - a few keybinds;
   - a cycle (the same key repeatedly);
   - drag-to-edge snapping;
   - the preview.
4. Try each action in **Windows ›**.
5. Revoke Accessibility. Windows turns off and the orange pill reads "Windows needs Accessibility". Grant it again: Windows resumes.
6. Open **General → Shortcuts**. Everything is listed, and conflicts, if any, are flagged.

## Out of scope

- `mooring win`, MCP window tools, saved layouts and undo of arrangements (3b).
- Stash and focus switching (later).
- The clipboard shortcut on the Shortcuts page (stage 4).
- Upstreaming changes to Loop.

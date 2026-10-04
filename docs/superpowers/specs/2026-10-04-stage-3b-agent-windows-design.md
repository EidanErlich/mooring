# Stage 3b: Agent windows

Oct 4, 2026 · Eidan Erlich · Status: design decided under the owner's standing instruction to complete the project end to end (decisions follow SPEC.md 3.4 and the decisions made so far)

## Goal

An agent arranges your windows from a plain request: "Chrome on the right half, iTerm bottom left, Slack top left". It reads the current windows, sends **one** plan, and tells you what landed. Mooring holds the Accessibility permission and does the matching and moving through WindowKit; the agent never needs Accessibility itself. The same commands work from your Terminal, and from MCP clients.

This builds on 3a (WindowKit, `WindowsController`), and follows SPEC.md 3.4.

## Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Where the work happens | **In the app**, through new socket ops `win.list`, `win.arrange`, `win.undo` and `win.layout` (names SPEC already reserves). The CLI and MCP server only relay. | Only the app holds Accessibility and WindowKit. |
| When Windows is off | Every `win` op fails with `denied`: "Windows is off. Turn it on in Mooring (Windows › Turn On…)." It never turns Windows on by itself. | Off means off (3a). Turning it on needs a person and Accessibility. |
| Agent control | The existing `AwakeSettings.agentWindows` (`automatic` · `askFirst` · `off`), shown in Settings → Agents as "Window arrangement by agents". People are never asked. Under Off an agent gets nothing, not even `win.list`. | Already in SPEC's table and in the settings model. |
| Ask first | A notification (category `mooring.window-approval`): "<Agent> wants to arrange 3 windows", with a body listing the placements (agent text without control characters, at most 40 characters each, and "May open apps that aren't running." when the plan launches or is a layout), and buttons **Allow** and **Deny**. It waits 60 s; no answer → `denied`. | Same pattern as 2c-1 lid approvals. |
| Who is an agent | The same detection as 2c-1 (ancestry, MCP `client`, links). | One rule everywhere. |
| Exit codes | `win arrange` exits 0 only when every placement is `ok`; 2 when any is `partial`, `ambiguous`, `not_running`, `not_found` or `failed`; 1 for a bad plan. | SPEC: "exits 0 only when every placement is ok". Exit 2 already means "done, but not fully". |
| Undo | The last 10 arrangements, in memory (window id → previous frame), lost on quit. `win undo` reverts the latest. | SPEC engineering decision. |
| Layouts | Stored in `~/Library/Application Support/Mooring/layouts.json`: name → placements (bundle id, screen, region or frame). `save` captures the frontmost window of each visible app on each screen, as screen fractions. `apply` checks them as any plan (`WinPlan.validated()`; otherwise `bad_request` "Layout <name> is invalid: …") and runs them with `launch: true`. | SPEC 3.1 "saved layouts". |
| Preview | `--preview` shows Loop's preview overlay on each target frame for 0.6 s before moving. | SPEC flag, using what WindowKit has. |
| Launch | `launch: true` opens apps that aren't running (`NSWorkspace`), and waits up to 10 s for a window. | SPEC. |
| Timeouts | `WindowKit.start()` sets a 1.5 s Accessibility messaging timeout on the system-wide element, the process default, so Loop's own calls are bounded too. `win list`, every mutating CLI request and every MCP window tool use a 120 s client. | A hung app can't stall the main actor for long; a list can wait on several hung apps. |
| Version | App 0.0.5, plugin 0.0.4 (skill change). | Version rule. |

## The flow

1. **Look.** `mooring win list --json` returns `apps[]` (name, bundle id, pid, windows[]: id, title, frame, screen, minimized, fullScreen) and `screens[]` (id, name, visibleFrame, position: `main`/`left`/`right`/index).
2. **Plan.** The agent writes one plan (SPEC schema: `placements[]` with `app`, `region` or `frame`, optional `screen`, optional `title`; plus `launch` and `preview`).
3. **Execute.** The app resolves every placement first, then applies all moves in one pass. A minimized window is restored first. A full-screen window is reported `failed` ("is full screen").
4. **Report.** One result per placement: `ok` (with final frame), `partial` (the app enforces a minimum size; final frame given), `ambiguous` (candidates listed, with a `reason` of "matches several apps: …" or "matches several windows: …"), `not_running`, `not_found` or `failed` (reason).

**Matching `app`:** case-insensitive. An exact name or bundle id wins. Otherwise a fuzzy prefix or substring match on the name, or on the last bundle-id component ("iterm" → iTerm2 `com.googlecode.iterm2`, "vscode" → Visual Studio Code `com.microsoft.VSCode`; "code" matches Visual Studio Code and Xcode). Ties → `ambiguous`, with candidates; never guessed.

**`region`** is a WindowKit action name that only sets a window's frame (`left-half`, `right-half`, `top-left`, `bottom-left`, …, `maximize`, `almost-maximize`, `center`, thirds and two-thirds, fourths, size and move steps, screen switches), so `win undo` can put it back. Minimize, hide, macOS full screen, Spaces, Loop's undo and initial frame, focus, stash and cycles are `failed` with "region isn't available to agents". `mooring win list-regions` prints them all. **`frame`** gives fractions `{x, y, w, h}` of the screen's visible area, origin top-left.

**`screen`** is `main`, `left`, `right`, or a 0-based index. The default is the screen the window is on.

**`title`** picks one window, case-insensitively: an exact title first, else a substring. The default is the app's frontmost window.

## CLI

| Command | Does |
| --- | --- |
| `mooring win list [--json]` | Apps, windows, screens |
| `mooring win arrange <app>=<region>[@screen] … [--launch] [--preview] [--json]` | One plan from arguments |
| `mooring win arrange --plan <file or ->` | Same, from JSON |
| `mooring win <action> [--app <name>] [--screen …]` | One action on one window (default: the frontmost app) |
| `mooring win undo` | Revert the last arrangement |
| `mooring win layout save \| apply \| list \| delete <name>` | Saved layouts |
| `mooring win list-regions` | Every region name |

The human output for `arrange` is one line per placement ("chrome ok", "iterm ok (was minimized, restored)", "code ambiguous: matches several apps: Visual Studio Code, Xcode", "notes isn't running").

## MCP tools

Added to `mooring mcp` (the fixed tool list grows from 4 to 9):
- `list_windows`;
- `arrange_windows(placements, launch, preview)`;
- `undo_arrangement`;
- `save_layout(name)`;
- `apply_layout(name)`.

Results are text, plus `structuredContent` with the per-placement results. The test that pins the tool list is updated to exactly 9 names, still with no clipboard.

## Skill

`SKILL.md` gains a short "Arranging windows" section:
- list first;
- send one plan;
- report every placement that isn't `ok`;
- offer `mooring win undo`;
- if Windows is off, tell the user to turn it on from the menu bar.

## Settings → Agents

"Window arrangement by agents": Automatic · Ask first · Off, with the caption "Agents can move and resize your windows with `mooring win` and MCP. Windows must be on."

## Components

| Piece | Where | Does |
| --- | --- | --- |
| Wire | MooringIPC | `Op.winList/winArrange/winUndo/winLayout` (`win.list` etc. on the wire); `WinPlan`, `WinPlacement`, `WinPlacementResult`, `WinArrangeResult`, `WinListArgs`, `WinListResult`, `WinLayoutArgs`, `WinLayoutResult`, `WinUndoArgs` |
| `WindowSystem` | WindowKit (public) | A protocol over enumerating apps, windows and screens, moving a window and applying a region; a live implementation via Loop's `Window` / AX and its resolver |
| `Arranger` | App, pure over `WindowSystem` | Match, resolve, apply, report; the undo stack; layouts |
| Handler | `App/IPC/RequestHandler+Windows.swift` | Gating (Windows on, agent mode, ask), dispatch |
| Window approval | `App/IPC/` | The `askFirst` notification, reusing `LidApprovalCenter`'s poster and waiting |
| CLI | MooringCLICore `WinCommands.swift` | The subcommands |
| MCP | MooringCLICore `MCP/` | 5 tools |

## Testing

- **`ArrangerTests`**, over a fake `WindowSystem` (two screens, several apps):
  - exact, fuzzy and ambiguous matching;
  - a region on a chosen screen;
  - fractional frames;
  - restoring a minimized window;
  - full screen → `failed`;
  - a minimum-size app → `partial`;
  - not running, with and without `launch`;
  - title selection;
  - undo restores and caps at 10;
  - layouts save, apply, list and delete (on a temporary file).
- **Handler:**
  - Windows off → `denied` with the message;
  - agent `off` → `denied` "Window arrangement by agents is off in Settings";
  - `askFirst`: Allow applies, Deny and timeout give `denied`;
  - a person is never asked.
- **CLI:** argument plans parse (`app=region@screen`), and exit codes are 0, 2 and 1.
- **MCP:** 9 tools; `arrange_windows` relays one plan.
- **Live:** with Accessibility granted, arranging three TextEdit windows returns `ok` frames, and `undo` restores them. This runs in the owner check: the test runner can't hold Accessibility.

## Owner check

1. Turn Windows on.
2. Ask Claude: "Put Chrome on the right half, iTerm bottom left and Slack top left". It calls `mooring win list`, then one `arrange`, and reports. Then say "undo".
3. Set "Window arrangement by agents" to Ask first, and repeat. A notification appears; Allow, then Deny.
4. Run `mooring win layout save coding`, move things, then `mooring win layout apply coding`.

## Out of scope

- Stash and focus switching.
- A global hotkey for layouts.
- Arranging windows on other Spaces.

# Stage 2b: the Claude Code plugin

Oct 2, 2026 · Eidan Erlich · Status: design approved in conversation; spec awaiting owner review

## Goal

With the plugin installed, every Claude Code session keeps the Mac awake while Claude works, with no prompting. A skill teaches Claude the hold and `anchor` patterns for longer jobs.

Success is SPEC.md 2.8:

- closing the lid mid-task keeps Claude working (once lid mode is allowed for agents, which comes in 2c);
- the Mac sleeps within 2 minutes of Claude stopping;
- killing Claude ends its lease at once;
- a session stuck at a permission prompt lets the Mac sleep after the waiting timeout;
- hooks add under 50 ms and never show an error in Claude Code;
- `mooring doctor` diagnoses a missing plugin.

This builds on stage 2a: the socket, the `mooring` CLI, named leases with `--watch-pid auto`, and the merge-on-re-acquire rule.

## Owner decisions (2026-10-02)

| Question | Decision |
| --- | --- |
| How the plugin is installed | **Both.** A button in Settings → Awake → Agents installs it from inside `Mooring.app`, so its version always matches the app. The repo also publishes a marketplace for `/plugin marketplace add EidanErlich/mooring`. |
| What the menu shows for a session | **The project folder:** "Claude Code · <folder>". No prompt text is ever stored or shown. |
| The Settings → Awake → Agents page | The install and status row, plus "Keep awake while agents work: Automatic / Only when asked", plus "When Claude is waiting for you, stay awake for: 10 / 30 / 60 min" (default 30). |
| Where the hook logic lives | **In the app.** `mooring hook <event>` forwards the raw event, and a pure `HookPolicy` in AwakeKit decides what happens. |

## Facts that shape the design

- **Hook events in the current docs:** `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `SubagentStop`, `Notification`, `Stop`, `SessionStart`, `SessionEnd` and `PreCompact`.
  - Missing from the docs: `PostToolBatch`, `SubagentStart`, `PermissionRequest` and `StopFailure`, all of which SPEC 2.3 assumed.
  - Docs can lag releases, so task 1 records real payloads from the installed Claude Code (2.1.284) before anything relies on a field.
- **Hooks run outside Claude's Bash sandbox,** so they can always reach the socket. Commands Claude runs itself (holds, `anchor`) can be sandboxed; the user allows `~/Library/Application Support/Mooring/mooring.sock` with `sandbox.network.allowUnixSockets`.
- **Hook stdout is parsed by Claude Code,** so a hook must print nothing. Exit 0 with no output never affects Claude.
- **Hook timeouts are in seconds,** and `"async": true` runs a hook in the background.
- **Process tree:** hooks are spawned through a shell by the `claude` process, so `--watch-pid auto` resolves Claude itself.
- **Installing from the command line:**
  - `claude plugin marketplace add <path|owner/repo> -y`
  - `claude plugin install <plugin>@<marketplace> -y`
  - `claude plugin list --json` reports `id`, `version`, `enabled` and `installPath`.
  - `claude --version` prints `2.1.284 (Claude Code)`.

## Lease lifecycle

One lease per session, `claude-<session_id>`:

- owner `.agent(name: "Claude Code")`;
- reason "Claude Code · <last path component of cwd>";
- level `system` (lid for agents arrives with 2c);
- watched pid: the nearest non-shell ancestor of the hook, i.e. the Claude process.

| Event | Action |
| --- | --- |
| `UserPromptSubmit` | Acquire: watched, expiry 15 min. Re-acquire merging applies, so it never shortens an existing lease. |
| `PreToolUse`, `PostToolUse`, `SubagentStop`, `PreCompact` | Renew: expiry = now + 15 min. If the lease is gone, acquire it as for `UserPromptSubmit`. |
| `Notification` for a permission prompt | Expiry = now + the waiting timeout (Settings, default 30 min). |
| `Notification` for an idle prompt | **Ignored.** Claude sends it after finishing a turn, while it waits for the next message. Counting it as waiting would keep the Mac awake for 30 min after every turn. |
| `Notification` of any other type | Ignored. |
| `Stop` | Release after 2 min, so the grace period covers background shells and quick follow-ups. |
| `SessionEnd` | Release now. |
| `SessionStart` or any unknown event | Ignored, so a future Claude Code version can't break anything. |

- **"Only when asked":** every hook request is acknowledged and does nothing. Agent holds and `mooring anchor` still work.
- **Crashes:** if Claude dies, the watched pid exits and the lease ends at once. If the pid can't be resolved, the 15 min expiry is the backstop.
- **Task 1 confirms the exact event names, notification type values and field names.** If they differ from this table, the owner reviews the change before it's built.

## Components

| Piece | Where | Does |
| --- | --- | --- |
| Hook wire op | `MooringIPC`: `Op.hook`, `HookArgs { event, sessionId, cwd, notificationType?, watchPid? }`, `HookResult { action }` | Additive to protocol v1. Unknown fields are ignored. |
| `HookPolicy` | AwakeKit, pure | `(event, notificationType, settings, leaseExists) → HookAction`, where the action is `acquire`, `renew`, `setExpiry(seconds)`, `releaseAfter(seconds)`, `releaseNow` or `ignore`. |
| Agent settings | `AwakeSettings` (AwakeKit) plus the Defaults key `awake` | `agentsAutomatic: Bool = true` and `agentWaitingTimeout: TimeInterval = 1800`. Both decode from older saved settings with these defaults. |
| Request handler | `App/IPC/RequestHandler.swift` | Handles `op: hook`: builds the session lease, applies the `HookPolicy` action through the existing engine API (acquire with merge, `renew`, `shorten`, `release`), and replies `HookResult`. Caller policy applies as for named leases (reserved ids, the 4 h cap, the 32-lease limit). |
| `mooring hook <event>` | `MooringCLICore` | Reads up to 1 MiB of JSON from stdin. Takes `session_id`, `cwd` and the notification type. Resolves the watched pid the same way as `--watch-pid auto`. Sends `op: hook` without launching the app and with a 1.5 s reply limit. **Always exits 0 and never prints to stdout;** errors go to the `ipc` log. Hidden from `--help`. |
| Plugin | `Integrations/claude-code-plugin/` | `.claude-plugin/plugin.json` (name `mooring`, version = app version, `testedWith`), `hooks/hooks.json`, `scripts/mooring-hook` and `skills/mooring/SKILL.md`. |
| `mooring-hook` | `scripts/mooring-hook`, POSIX `sh` | Finds `mooring` (see below), then `exec mooring hook "$1"`. With no `mooring` found, exits 0 silently. |
| Repo marketplace | `.claude-plugin/marketplace.json` at the repo root | Marketplace `mooring`, plugin `mooring`, source `./Integrations/claude-code-plugin`. |
| Bundled marketplace | `Mooring.app/Contents/Resources/ClaudePlugin/` (a copy-files build phase) | The plugin folder plus its own `marketplace.json`, with marketplace `mooring-app`. |
| Plugin installer | `App/Settings/ClaudePluginInstaller.swift` | Finds `claude`, reads the plugin status, installs or updates. Pure parsing of the CLI's output, plus a thin `Process` runner. |
| Agents page | `App/Settings/AgentsSettingsPage.swift`, in the Awake group | The plugin row and the two settings. |
| `doctor` | `MooringCLICore` `Doctor` | Check 5 becomes real, plus a Claude Code version warning. |

### How `mooring-hook` finds `mooring`

It tries these in order, using the first that is executable:

1. `$MOORING_BIN`
2. `~/.local/bin/mooring`
3. `mooring` on `PATH`
4. `<the app containing this script>/Contents/Helpers/mooring`, when the script lives inside `Mooring.app/Contents/Resources/ClaudePlugin/`
5. `/Applications/Mooring.app/Contents/Helpers/mooring`

### `hooks/hooks.json`

- **Synchronous, `timeout: 2`:** `UserPromptSubmit`, `Stop`, `Notification`.
- **`SessionEnd`:** synchronous, `timeout: 1`.
- **Background (`"async": true`):** `PreToolUse`, `PostToolUse`, `SubagentStop`, `PreCompact`.
- Every command is `${CLAUDE_PLUGIN_ROOT}/scripts/mooring-hook <EventName>`.

### Skill, `skills/mooring/SKILL.md`

About 30 lines. It says:

- **The Mac stays awake automatically** while you work in this session. Don't disable Mooring or change its settings.
- **A job that will outlive your turn** (a background build, a long download, a watcher): wrap it in `mooring anchor --reason "…" -- <cmd>`.
- **A long multi-step job held as one unit:** `mooring lease acquire job-<slug> --watch-pid auto --reason "…"`. When it's done, success or failure, always run `mooring lease release job-<slug>`.
- **Call `mooring` directly,** never through `timeout`, `xargs`, `npx` or a script. A wrapper would become the watched process.
- **"Can't reach Mooring's socket (permission denied)":** tell the user to allow `~/Library/Application Support/Mooring/mooring.sock` in `sandbox.network.allowUnixSockets`. Don't retry in a loop.
- **Exit 2** means a guardrail paused the hold. The hold still exists and still needs releasing.

### Settings → Awake → Agents

**The Claude Code plugin row:**

- **Status:** "Installed (from the app)", "Installed (from GitHub)", "Needs update" (installed version ≠ app version), "Not installed", or "Claude Code not found".
- **Button:** Install, Update or Reinstall. When the GitHub copy is installed, the row shows that and offers no button.
- **Finding `claude`:**
  1. `zsh -lc 'command -v claude'`
  2. then `~/.local/bin/claude`
  3. then `/opt/homebrew/bin/claude`
  4. then `/usr/local/bin/claude`
- **Install:** runs `claude plugin marketplace add <bundle>/Contents/Resources/ClaudePlugin -y`, then `claude plugin install mooring@mooring-app -y`. On failure it shows the command's stderr.
- **Update** re-runs the same pair.
- **Status** is read from `claude plugin list --json` when the page appears and after install.

**The two settings:**

- **"Keep awake while agents work":** Automatic / Only when asked.
- **"When Claude is waiting for you, stay awake for":** 10 / 30 / 60 min.

### `doctor` check 5, "Claude plugin"

- ✓ when `claude plugin list --json` shows `mooring@mooring-app` or `mooring@mooring` enabled.
- ✗ "not installed", fix "Settings → Awake → Agents → Install".
- – "Claude Code not found".
- **A separate warning line** appears when `claude --version`'s major or minor version differs from `testedWith` in the installed `plugin.json`.

## Testing

- **Task 1, the payload test (throwaway):**
  1. A local plugin with a hook on every documented event appends stdin JSON and the hook's process chain (`ps -o pid,ppid,comm`) to a scratch file.
  2. Run one short Claude session: a prompt, a tool call, a subagent, a permission prompt, then exit.
  3. Record the event names, field names, notification types and parent chain in the spec's facts section, and keep anonymized payloads as test fixtures.
  4. Uninstall the throwaway plugin.
- **`HookPolicyTests`:**
  - every table row;
  - "Only when asked";
  - the waiting timeout from settings;
  - idle and other notifications ignored;
  - unknown events ignored.
- **`MooringIPC`:** the `hook` request and result round-trip, and unknown fields are tolerated.
- **`MooringCLICore`, `mooring hook`:**
  - parses the recorded fixtures;
  - stdout is empty in every case;
  - exits 0 on bad JSON, an unreachable app, a blocked socket, a silent app (gives up within 1.5 s) and oversize input;
  - never launches the app;
  - resolves its watched pid;
  - completes in under 50 ms against a local test server (asserted with a CI margin).
- **`RequestHandler` hook tests:**
  - one session's full life: prompt, tools, a permission prompt, stop (2 min grace), a new prompt within the grace;
  - session end;
  - two concurrent sessions;
  - "Only when asked";
  - reserved and invalid ids refused.
- **`mooring-hook` script test** (`scripts/test-mooring-hook.sh`, run by `make test`): fake `mooring` binaries at each search location are found in order, and with none present it exits 0 silently.
- **`ClaudePluginInstallerTests`:**
  - finding `claude` with injected lookups;
  - parsing canned `claude plugin list --json` and `claude --version` output;
  - the exact install command lines;
  - nothing is executed.
- **`DoctorTests`:** plugin pass, fail and skip, plus the version warning.
- **Repo marketplace:** `marketplace.json` and `plugin.json` parse as JSON with the required fields, and the bundled copy matches the source folder.

## Owner check

1. Settings → Awake → Agents → Install. `mooring doctor` shows ✓ Claude plugin.
2. Start a Claude task. The menu shows "Claude Code · <folder>".
3. When Claude finishes, the lease shows about 2 min left, then disappears.
4. Kill or quit Claude mid-task. Its lease ends immediately.
5. Leave Claude at a permission prompt. The lease shows about 30 min.
6. Switch to "Only when asked". A new prompt creates no lease.
7. Optional: `/plugin marketplace add EidanErlich/mooring` and `/plugin install mooring@mooring` work from GitHub. Uninstall the app copy first.

## SPEC.md changes

- **2.3:**
  - the event table with the verified events and the idle-prompt rule;
  - the reason "Claude Code · <folder>";
  - both install paths;
  - `mooring hook` and `op: hook`;
  - the hooks.json sketch updated.
- **Agent control and approvals:** the two new settings ("Keep awake while agents work" now has Automatic / Only when asked, and there is a waiting timeout).
- **Engineering decisions:** the `hook` op, and `HookPolicy` in AwakeKit.
- **Stages:** row 2b.

## Out of scope

- Lid mode for agent sessions, and the approval notifications (2c).
- `mooring mcp` and the plugin's `.mcp.json` (2c).
- Adapters for other agents, and the `AGENTS.md` snippet (2.4).
- Push notifications (2.7).

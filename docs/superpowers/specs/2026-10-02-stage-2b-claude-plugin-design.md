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
| What the menu shows for a session | **The project folder:** "Claude Code · <folder>" ("Claude Code · session 1a2b" with no folder). No prompt text is ever stored or shown. |
| The Settings → Awake → Agents page | The install and status row, plus "Keep awake while agents work: Automatic / Only when asked", plus "When Claude is waiting for you, stay awake for: 10 / 30 / 60 min" (default 30). |
| Where the hook logic lives | **In the app.** `mooring hook <event>` forwards the raw event, and a pure `HookPolicy` in AwakeKit decides what happens. |

## Facts that shape the design

**Recorded from Claude Code 2.1.285 on 2026-10-02.** The fixtures live in `Packages/MooringIPC/Tests/MooringCLICoreTests/Fixtures/hooks/`.

- **Events that fire:**
  - `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `Notification`, `PostToolUse`, `PostToolBatch`, `SubagentStart`, `SubagentStop`, `Stop` and `SessionEnd`.
  - `PreCompact` is documented.
  - `StopFailure` didn't occur in the test. Claude Code documents it as firing instead of `Stop` when a turn ends on an API error, so it follows the `Stop` rules.
  - The docs were wrong to omit `PostToolBatch`, `SubagentStart` and `PermissionRequest`.
- **Fields on every event:** `session_id`, `cwd`, `hook_event_name`, `transcript_path`, `prompt_id`, and usually `permission_mode`.
- **Per-event fields:**
  - `UserPromptSubmit`: `prompt`. It is never used.
  - `Notification`: `notification_type` (`permission_prompt` observed) and `message`.
  - `SessionEnd`: `reason` (`prompt_input_exit`, `other`).
  - Subagent events: `agent_id` and `agent_type`.
  - `Stop` and `SubagentStop`: `background_tasks`, an array of `{id, type, status, description}`.
- **Subagents can run in the background.** Then `Stop` fires while they still run, with `background_tasks` listing them as `running`. When they finish, Claude gets a synthetic `UserPromptSubmit` (a `<task-notification>`) and a second `Stop` with an empty list.
- **An internal helper agent runs after `Stop`:** Claude's prompt-suggestion agent. It carries an `agent_id` with an **empty `agent_type`**, and no `SubagentStart` comes before it.
- **The idle notification:** no `idle_prompt` fired in 90 s of idling. It is documented, and it is ignored either way.
- **Process chain:** `zsh → claude → /bin/sh (hook command) → script`. The hook's parent is the `claude` process, so `--watch-pid auto` resolves it directly.
- **The sandbox:** hooks run outside Claude's Bash sandbox, so they can always reach the socket. Commands Claude runs itself (holds, `anchor`) can be sandboxed; the user allows `~/Library/Application Support/Mooring/mooring.sock` with `sandbox.network.allowUnixSockets`.
- **Hook output:** stdout is parsed by Claude Code, so a hook must print nothing. Exit 0 with no output never affects Claude.
- **Hook options:** timeouts are in seconds, and `"async": true` runs a hook in the background.
- **The `claude` command line:**
  - `claude plugin marketplace add <path|owner/repo>` (no `-y`), `marketplace update [name]` and `marketplace list --json` (`[{name, source, …}]`)
  - `claude plugin install <plugin>@<marketplace> -y` and `claude plugin update <plugin>@<marketplace> -y` (an update needs a Claude Code restart)
  - `claude plugin list --json` reports `id`, `version`, `enabled` and `installPath`
  - `claude --version` prints `2.1.285 (Claude Code)`
  - `claude --plugin-dir <dir>` loads a plugin for one session

## Lease lifecycle

One lease per session, `claude-<session_id>`:

- owner `.agent(name: "Claude Code")`;
- reason "Claude Code · <last path component of cwd>", or "Claude Code · session <first 4 characters of the session id>" when there is no folder (cwd missing or `/`), so folderless sessions can be told apart;
- level `system` (lid for agents arrives with 2c);
- watched pid: the nearest non-shell ancestor of the hook, i.e. the Claude process.

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

- **Renewals only ever extend:** a renew sets the expiry to the later of its current value and its new one, so a short tool event never cuts a long Bash hold. Only the waiting timeout and the `Stop` grace set the expiry outright.
- **"Only when asked":** every hook request is acknowledged and does nothing. Agent holds and `mooring anchor` still work.
- **Crashes:** if Claude dies, the watched pid exits and the lease ends at once. If the pid can't be resolved, the 15 min expiry is the backstop.
- The owner approved the background-task `Stop` rule on 2026-10-02. The internal-agent rule was a controller ruling.

## Components

| Piece | Where | Does |
| --- | --- | --- |
| Hook wire op | `MooringIPC`: `Op.hook`, `HookArgs { event, sessionId, cwd, notificationType?, agentID?, agentType?, runningBackgroundTasks?, watchPid?, toolTimeout? }`, `HookResult { action }` | Additive to protocol v1. Unknown fields are ignored. |
| `HookPolicy` | AwakeKit, pure | `action(_ hook: HookEvent, settings:, leaseExists:) → HookAction`. `HookEvent` bundles the event name, `notificationType`, `agentID`, `agentType`, the running background-task count and `toolTimeout`. The action is `acquire`, `renew`, `renewFor(seconds)`, `setExpiry(seconds)`, `releaseAfter(seconds)`, `releaseNow`, `ignore` or `skipped` ("Only when asked"). |
| Agent settings | `AwakeSettings` (AwakeKit) plus the Defaults key `awake` | `agentKeepAwake: AgentMode = .automatic` and `agentWaitingTimeout: TimeInterval = 1800`. Both decode from older saved settings with these defaults. |
| Request handler | `App/IPC/RequestHandler.swift` | Handles `op: hook`: builds the session lease, applies the `HookPolicy` action through the existing engine API (acquire with merge, `renew`, `shorten`, `release`), and replies `HookResult`. Caller policy applies as for named leases (reserved ids, the 4 h cap, the 32-lease limit). |
| `mooring hook <event>` | `MooringCLICore` | Reads up to 1 MiB of JSON from stdin. Takes `session_id`, `cwd` and the notification type. Resolves the watched pid the same way as `--watch-pid auto`. Sends `op: hook` without launching the app and with a 1.5 s reply limit. **Always exits 0 and never prints to stdout;** errors go to the `hook` log category. Hidden from `--help`. |
| Plugin | `Integrations/claude-code-plugin/` | `.claude-plugin/plugin.json` (name `mooring`, version = app version), `mooring.json` (`testedWithClaudeCode`), `hooks/hooks.json`, `scripts/mooring-hook` and `skills/mooring/SKILL.md`. |
| `mooring-hook` | `scripts/mooring-hook`, POSIX `sh` | Finds `mooring` (see below), then runs `mooring hook "$1"` (not `exec`) with all output discarded, and always exits 0. With no `mooring` found, exits 0 silently. |
| Repo marketplace | `.claude-plugin/marketplace.json` at the repo root | Marketplace `mooring`, plugin `mooring`, source `./Integrations/claude-code-plugin`. |
| Bundled marketplace | `Mooring.app/Contents/Resources/ClaudePlugin/` (a copy-files build phase) | The plugin folder plus its own `marketplace.json`, with marketplace `mooring-app`. |
| Plugin installer | `App/Settings/ClaudePluginInstaller.swift` | Finds `claude`, reads the plugin status, installs or updates. Pure parsing of the CLI's output, plus a thin `Process` runner. |
| Agents page | `App/Settings/AgentsSettingsPage.swift`, in the Awake group | The plugin row and the two settings. |
| `doctor` | `MooringCLICore` `Doctor` | Check 5 becomes real, plus a Claude Code version warning. It passes if either the app's or the GitHub copy is enabled, and is skipped ("couldn't check") when `claude plugin list` fails. |

### How `mooring-hook` finds `mooring`

It tries these in order, using the first that is executable:

1. `$MOORING_BIN`
2. `~/.local/bin/mooring`
3. `mooring` on `PATH`
4. `<the app containing this script>/Contents/Helpers/mooring`, when the script lives inside `Mooring.app/Contents/Resources/ClaudePlugin/`
5. `/Applications/Mooring.app/Contents/Helpers/mooring`

### `hooks/hooks.json`

- **Synchronous, `timeout: 2`:** `UserPromptSubmit`, `Stop`, `StopFailure`, `Notification`, `PermissionRequest`.
- **`SessionEnd`:** synchronous, `timeout: 1`.
- **Background (`"async": true`, `timeout: 5`):** `PreToolUse`, `PostToolUse`, `PostToolBatch`, `SubagentStart`, `SubagentStop`, `PreCompact`.
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
- **Install, Update and Reinstall** are one flow, and stop at the first command that fails (the page shows its stderr, or "Timed out" or "Failed (exit N)" when stderr is empty):
  1. Link `mooring` onto the PATH.
  2. `claude plugin marketplace list --json`. If `mooring-app` isn't listed, `claude plugin marketplace add <bundle>/Contents/Resources/ClaudePlugin`; otherwise `claude plugin marketplace update mooring-app`. If it is listed with a different `path` (the app was moved), run `claude plugin marketplace remove mooring-app` (which also uninstalls its plugins) and then `add` the new path, so step 3 installs afresh.
  3. `claude plugin list --json`. If `mooring@mooring-app` isn't listed, `claude plugin install mooring@mooring-app -y`; otherwise `claude plugin update mooring@mooring-app -y`.
  4. After a successful Update the page says "Restart Claude Code sessions to use the new version."
- `claude` runs with its own folder first on `PATH` (so an npm-installed `claude` finds the `node` beside it), then the usual Homebrew and system folders.
- **Status** is read from `claude plugin list --json` when the page appears and after install.

**The two settings:**

- **"Keep awake while agents work":** Automatic / Only when asked.
- **"When Claude is waiting for you, stay awake for":** 10 / 30 / 60 min.

### `doctor` checks 5 and 6

**Check 5, "Claude plugin":**

- ✓ "<id> <version>" when `claude plugin list --json` shows `mooring@mooring-app` or `mooring@mooring` enabled.
- ✗ "not installed" (or "disabled" when it is installed but switched off), fix "Settings → Awake → Agents → Install".
- – "Claude Code not found".

**Check 6, "Claude Code version":**

- ✓ "<version>" when `claude --version`'s major.minor equals `testedWithClaudeCode` in the installed plugin's `mooring.json`.
- – "tested with <testedWith>; you have <version>" when the major.minor differs. It is a warning, not a failure, so a Claude Code update never makes `doctor` exit 1 on its own.
- – "unknown" when either value is missing.

`mooring` finds `claude` on its own `PATH`, then in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`, and runs each `claude` command with a 3 s limit.

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

# Stage 2a: IPC and the `mooring` CLI

Oct 1, 2026 · Eidan Erlich · Status: design approved in conversation; spec awaiting owner review

## Goal

A `mooring` command that scripts, terminals and agents use to keep the Mac awake. It talks to the running app over a local socket, and every request becomes a lease in the same engine the menu uses. The menu shows who holds each lease, and only the app ever talks to the root helper.

Stage gate (SPEC.md, Stages, 2a): `mooring anchor -- sleep 20` shows in `mooring status --json`, and exit codes match 2.2.

SPEC.md 2.1, 2.2, 2.6 and Engineering decisions ("Socket protocol") already fix the socket path and modes, the peer-uid check, the newline-delimited JSON shapes, the commands and the exit codes. This spec fills the gaps and records the owner's decisions.

## Owner decisions (2026-10-01)

| Question | Decision |
| --- | --- |
| How far to trust commands typed in a terminal before approvals exist (2c) | **Like the menu.** `on`, `off` and `anchor` may run until turned off and may use lid mode. `on` and `off` are the menu's On switch (the `menu` session), not a separate lease. Named `lease` leases (what agents use) keep the 2.6 limits: a 4 h cap, and lid refused until 2c. |
| Where "Install command-line tool" puts `mooring` | **`~/.local/bin`, no password.** If that folder isn't on PATH, Settings shows the line to add to `~/.zshrc`. |
| Agents holding the Mac awake for a whole job | **Agent holds**: a named lease tied to the agent's own process, released by the agent when everything is done (below). |
| Lease rows rebuilt on every change (deferred from #6) | **Fold the fix in**: rows update in place by id. |

## Agent holds

Everything an agent does for a job runs inside the agent's own process tree: subagents, tool calls, scripts. So there are two patterns, both callable from any agent's shell:

| Need | Command | Ends when |
| --- | --- | --- |
| A whole job (an analysis with subagents, scripts and many commands) | `mooring lease acquire job-churn --watch-pid auto --reason "Churn analysis"` at the start; `mooring lease release job-churn` when everything is finished | The agent releases it, or the agent process exits (crash, `/exit`, killed). Safety cap 4 h, extendable with `mooring lease renew job-churn`. |
| One long command, including a background script that outlives the agent's turn | `mooring anchor -- ./run-analysis.sh` | The command exits. `anchor` returns its exit code. |

- **`--watch-pid auto`** resolves the nearest ancestor that isn't a shell. For Claude Code's Bash tool, that is the Claude process.
- **Repeated acquires:** re-acquiring the same id renews it without weakening it, so nested steps never end each other's hold (rule under Commands). Different ids are separate holds.
- **Help text:** `mooring --help` has a short "For agents" section with exactly these two patterns.
- **2b follow-up:** the Claude plugin's skill teaches these patterns, and its `SessionEnd` hook releases holds created in that session.

## Components

| Piece | Where | Does |
| --- | --- | --- |
| Wire format | `Packages/MooringIPC`, target `MooringIPC` (exists; a stub today) | `Request` / `Response` / `WireError` types per Engineering decisions, newline framing (max 64 KiB per line), `DurationText.parse`, level parsing, error code → exit code. Pure. |
| CLI core | Same package, new target `MooringCLICore`, using `swift-argument-parser` | Subcommands, `--watch-pid auto` (over an injectable process table), owner naming, human and `--json` output, socket client, auto-launch, and `anchor`'s child process and signal forwarding. |
| `mooring` binary | `CLI/main.swift`, new tool target in `project.yml` | Thin entry point that maps every error to the right exit code. Copied to `Mooring.app/Contents/Helpers/mooring` and signed with the app. It is not in `Contents/MacOS` because `MacOS/Mooring` and `mooring` collide on case-insensitive volumes. The Xcode target is `MooringCLI` (product name `mooring`). |
| Socket server | `App/IPC/SocketServer.swift` | See below. |
| Request handler | `App/IPC/RequestHandler.swift`, `@MainActor` | Turns requests into engine calls through the caller policy and builds responses. |
| Caller policy | `Packages/AwakeKit`, pure | See Policy. |
| Lease TTL | `Lease.ttl: TimeInterval?` (AwakeKit) | The TTL last granted, so `renew` without `--ttl` reuses it. Optional; older `leases.json` files decode with nil. |
| CLI install | Settings → General | "Install command-line tool" symlinks `~/.local/bin/mooring` to the bundled binary, creating the folder if needed. It shows whether the link is installed, missing, or points elsewhere, plus the PATH line with a Copy button, always (a GUI app can't see the shell's PATH; `mooring doctor` is the real check). |
| Lease rows fix | `DropdownMenu`, `LeaseRow` | Rows update in place by id, so renewals and guardrail changes don't rebuild them. `LeaseRow` takes the engine and an id and reads the lease live. |

### Socket server

- **Location:** creates `~/Library/Application Support/Mooring/` with mode `0700` and binds `mooring.sock` with mode `0600`.
- **A stale socket** (one that refuses connections) is unlinked first. A path that is a symlink or not a socket is refused and logged.
- **Threading:** listens on a serial DispatchQueue with an accept source, reads off the main thread, and hops to the main actor for each request.
- **Peer check:** `getsockopt(LOCAL_PEERCRED)` must report the app's own uid, otherwise the connection closes without a reply. `LOCAL_PEERPID` provides the caller pid for `LeaseOwner.cli(pid:)`.
- **Limits:**
  - one request line per connection;
  - 64 KiB per line;
  - a 5 s read timeout;
  - at most 16 open connections (further connections are closed at once).
- **Lifetime:** starts at launch and removes the socket on quit.

## Policy

Pure and in AwakeKit, applied by the request handler:

| Rule | Trusted ops (`on`, `off`, `anchor`) | Named leases (`lease acquire/renew/release`) |
| --- | --- | --- |
| Until turned off | Allowed | Not allowed: `--ttl` or `--watch-pid` is required |
| Max length | Engine max (12 h) | 4 h, including a watched lease with no TTL. Renewable. |
| Lid level | Allowed (guardrails apply) | `denied` until 2c |
| Ids | `menu` (`on`, `off`), `anchor-<pid>` | 1 to 64 characters of `[A-Za-z0-9._-]`. Reserved ids (`menu`, `lid-session`, `app-*`, `cli`, `anchor-*`) are refused as `bad_request`. |
| Lease count | A socket request that would take the table past 32 live leases gets `denied`. The menu is never refused. | Same |
| Reason | Trimmed to 80 characters, control characters stripped | Same |

## Commands

Shared behaviour:

- **Reaching the app:** if nothing listens on the socket, the CLI runs `open -gj -b dev.mooring.app` and waits up to 3 s. Otherwise it prints "Mooring isn't running and couldn't be started" and exits 3. `--no-launch` (used by 2b's hooks) skips the launch.
- **Three exit-3 messages:**
  - "Mooring isn't running and couldn't be started": connect fails with `ENOENT`, `ECONNREFUSED` or `ENOTSOCK` (after the launch and retry), or the path is too long. Any other connect error counts here too.
  - "Mooring didn't answer. It may be busy; the request may have gone through, so check `mooring status`.": connected, but the write failed, the reply timed out, ended before a newline, was over `maxLineBytes`, or wouldn't decode.
  - "Can't reach Mooring's socket (permission denied). If this runs in a sandbox, allow ~/Library/Application Support/Mooring/mooring.sock": connect fails with `EPERM` or `EACCES`; never retried or launched.

  `anchor` treats all three as "not reachable" and doesn't start the command. `doctor` treats all three as no status, with App detail "not running", "didn't answer" or "permission denied".
- **Waiting for a reply:** 5 s. 2c raises it to 60 s for approvals.
- **Flag placement:** `--json` and `--no-launch` go after the subcommand (`mooring status --no-launch`).
- **Output:** human text by default, with errors on stderr as `mooring: <message>`. With `--json`, stdout carries the `result`, or `{"ok":false,"error":{…}}`.
- **Usage errors under `--json`:** when `--json` is among the arguments, every usage error (ArgumentParser errors, bad durations, levels or pids, and execute-time ones such as "Couldn't find a process to watch") prints exactly one line on stdout, `{"ok":false,"error":{"code":"usage","message":"<message>"}}`, nothing on stderr, and exits 1. For ArgumentParser errors the message is the first line of the error, without the "Usage:" block. `--help` and `--version` are unchanged.
- **Exit codes:**
  - 0: success;
  - 1: usage error, `bad_request` or `not_found`;
  - 2: `guardrail` or `denied`;
  - 3: app unreachable;
  - 4: `internal`.
- **Durations:** `90s`, `15m`, `2h`, `1h30m`. A bare number, zero, a negative or an unknown unit is a usage error.
- **Owner label:** "Terminal" (`.cli(pid:)`) by default, which applies to `anchor` and `lease` without an agent; `on` and `off` act on the menu session, labelled "Menu bar". With `--watch-pid auto` it is `.agent(name:)`, named after the watched process: `claude` → "Claude Code", `codex` → "Codex", otherwise the process name. `--agent "<name>"` (trimmed to 40 characters) overrides it.

| Command | Lease | Behaviour |
| --- | --- | --- |
| `on [--level] [--for] [--reason]` | `menu` (owner `.menu`, reason "Turned on from the menu bar") | The menu's On switch: the same session a left click and the dropdown control. With no flags a running session is left alone and its lease is returned (the first picked app's lease when apps are picked); with none, one starts at the click defaults, as a left click does. With `--for` and/or `--level` the session is replaced, like picking a duration in the dropdown: picked apps are cleared, the duration is `--for` or the click duration, and the level is `--level`, else the session's level, else the click level. `--reason` is accepted and ignored. |
| `off` | ends the menu session | Ends the `menu` lease and any picked apps, like a left click while on. Also releases a `cli` lease an earlier build left. Idempotent: prints "Already off" and exits 0 when nothing was on. Never touches agent leases or anchors. |
| `anchor [--level] [--reason] -- <cmd …>` | `anchor-<childpid>`, watched | Checks the app is reachable first, so it fails fast with 3. The child inherits stdio, the working directory and the environment. INT, TERM and HUP are forwarded to it. Exits with the child's code. Level defaults to `system`, reason to the command line (trimmed). |
| `anchor --pid <pid>` | `anchor-<pid>`, watched | Returns immediately. Exits 1 if the process isn't running. |
| `lease acquire <id> (--ttl … \| --watch-pid <pid>\|auto) [--level] [--reason] [--agent]` | `<id>` | Policy above. Re-acquiring renews and never weakens: the later expiry wins (`max(granted, what the lease has left)`, still within the 4 h cap; a lease with no expiry keeps none), the existing watch is kept unless `--watch-pid` is given, the level is the union of old and new (policy runs on the union, so lid stays denied), `--reason` replaces the reason only when given, and the owner is kept unless `--agent` is given. `lease renew --ttl` stays an explicit reset; `on` and `anchor` are unchanged. A lease or `anchor --pid` acquire with a watch prints `Lease <id> · while <name> (<pid>) runs · <cap> cap` or `Anchored <id> · while <name> (<pid>) runs`, with `process <pid>` when the process can't be found. |
| `lease renew <id> [--ttl]` | | Reuses the last TTL when `--ttl` is omitted. Exits 1 if the lease is missing. |
| `lease release <id> [--after 2m]` | | `--after` only ever shortens the expiry. Releasing a lease that is already gone exits 0. |
| `status [--json]` | | See below. |
| `doctor [--json]` | | See below. |

**Guardrails.** If a guardrail holds back what was asked (lid mode while the battery is low, for example), the lease is still created and takes effect when the guardrail lifts. The CLI prints why ("Lid mode paused: battery low") and exits 2. The message also says the lease is held and how to end it (`mooring lease release <id>` or `mooring off`), so a caller that sees exit 2 still knows to release.

**`status`** in human form:

```
On · lid mode · 1h 12m left
Leases (3)
  Menu bar      Turned on from the menu bar   1h 12m left
  Terminal      sleep 20                      while running
  Claude Code   Churn analysis                while running · 4h cap
Battery 64% · Thermal nominal · Lid open · Helper enabled
Paused: lid mode (battery low)
```

`--json` returns:

- `summary` (the dropdown's first line, for example "On · lid mode · 1h 12m left");
- `effective {system, display, lid}`;
- `systemAssertion`, `displayAssertion` and `lidSleepDisabled` (read through the helper);
- `helperSleepDisabled` (what `doctor` compares with `lidSleepDisabled`) and `wantsLid` (some live lease asks for lid mode);
- `leases[]`, each with `id`, `owner {kind, name}`, `reason`, `level`, `expiresAt` (ISO 8601 or null), `watchPid` and `ttl`;
- `power {onAC, batteryPercent}`, `thermal`, `lidClosed`, `helper` and `suspensions[]`.

**`doctor`** prints one line per check (✓, ✗ or –), with the fix next to every ✗:

1. The app answers on the socket.
2. `mooring` on PATH resolves to this app's binary. Fix: Settings → Install command-line tool, or the PATH line.
3. The helper is approved.
4. The helper's reading of lid sleep matches the engine's applied state (`lidSleepDisabled`). Lid sleep disabled with no lid lease means it is stuck; fix: quit and reopen Mooring, which restores sleep. This reading comes from the app's status, which asks the helper; the CLI never runs `pmset`.
5. Claude plugin: "–, arrives in 2b".

Exit 0 when nothing failed, 1 otherwise.

## Testing

- **`MooringIPCTests`:**
  - request and response round-trips in the spec's shapes;
  - a missing or wrong `v`, malformed JSON, and lines over 64 KiB → `bad_request`;
  - durations (valid and invalid as listed above);
  - levels, including `display,lid`;
  - the exit-code mapping.
- **`MooringCLICoreTests`:**
  - parsing every command, with usage errors exiting 1;
  - `--watch-pid auto` over a fake process table (shell, shell, then `claude` resolves to `claude`; all shells is an error);
  - owner naming;
  - `status` and `doctor` output from canned responses, human and `--json`;
  - `anchor` with real tiny children: `sh -c 'exit 7'` exits 7, and an INT reaches a `sleep` child.
- **AwakeKit `CallerPolicyTests`:** every row of the Policy table, plus `Lease.ttl` defaulting to nil when decoding an old file.
- **App `RequestHandlerTests`:** a real engine with fakes:
  - each op;
  - renew reusing the TTL;
  - `--after` only shortening;
  - idempotent release;
  - `not_found`;
  - the guardrail response;
  - owner labels.
- **App `SocketServerTests`:** a real socket in a temporary folder:
  - modes `0700` / `0600`;
  - stale socket replaced;
  - full round trip;
  - an over-long line and a silent client dropped without blocking others;
  - the uid branch via an injected credential check.
- **App `DropdownMenuTests` (lease rows fix):**
  - a renewal keeps the same row view (`===`);
  - a guardrail change leaves the rows alone;
  - acquire adds one row and release removes one.
- **`scripts/cli-smoke.sh`**, run against the signed app:
  - `anchor -- sleep 20` is listed in `status --json`, then gone;
  - exit codes 0, 1, 2 and 3 (3 with the app quit and `--no-launch`).

## Owner check

1. Settings → Install command-line tool, then `mooring doctor` in a new terminal.
2. `mooring on --for 30m`: the pill and menu update. Then `mooring off`.
3. Ask Claude to run a multi-step job with `mooring lease acquire … --watch-pid auto`. The menu shows "Claude Code" with the reason. The lease ends on `release`, and also when Claude quits.
4. `mooring anchor -- sleep 60` keeps the Mac awake for 60 s and exits 0.

## SPEC.md changes

- **2.2:**
  - named leases need `--ttl` or `--watch-pid`;
  - `renew` reuses the last TTL;
  - `release` is idempotent;
  - `--no-launch`, `--agent` and the owner naming;
  - the install path is `~/.local/bin` only;
  - a "For agents" note with the two patterns.
- **2.6:** split the table into trusted ops and named leases, as above.
- **Engineering decisions:**
  - `not_found` maps to exit 1;
  - doctor reads lid sleep through the helper;
  - `MooringCLICore` and `swift-argument-parser`;
  - `Lease.ttl`.
- **Stages:** 2a gets agent holds and the lease-row fix. The URL scheme and App Intents move next to 2c.

## Out of scope

- The Claude Code plugin, hooks, skill and `SessionEnd` cleanup (2b).
- Approvals, lid mode for named leases, and `mooring mcp` (2c).
- The `mooring://` URL scheme and App Intents.
- The Homebrew symlink (stage 5).

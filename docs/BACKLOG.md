# Backlog

Small issues found in review and deferred. None of them blocked merge. The most user-visible ones are listed first in each section. Delete an item once it's fixed.

## Claude Code plugin (2b leftovers)
- `doctor`'s plugin detail can name the GitHub copy when both copies are enabled and `claude plugin list` lists it first; prefer the app copy explicitly.
- `doctor` still says "not installed" when both `claude --version` and `plugin list` fail; skip whenever the list is unavailable.
- SPEC.md's Esc paragraph says an interrupted turn keeps its lease "up to 15 min"; with renewals that only extend, it can last until a long Bash hold or the waiting timeout ends.
- No tests for the installer failing at `marketplace remove` (must stop before `add`) or at `add` after a successful remove.
- The moved-app check compares standardized paths without resolving symlinks, so a symlinked app path triggers a needless remove and reinstall.
- **An npm-installed Claude shows as "node"** for leases the skill creates (`LeaseCommands.swift` `agentName`). Hook leases are fine, because the owner is passed explicitly.
- **Async renew after the sync `Stop`.** An async `PostToolUse`, `PostToolBatch` or `SubagentStop` can land after the sync `Stop` for a very short final reply, which turns the 2 min grace into 15 min.
- **"Only when asked" mid-session** also skips the `Stop` and `SessionEnd` releases, so a lease made just before the switch lives out its expiry.
- **The internal-agent rule** relies on undocumented Claude Code behaviour (a helper agent with an `agent_id` and no `agent_type`). A typed helper agent would renew after every turn.
- **`SessionEnd`'s 1 s hook timeout** is shorter than the 1.5 s reply limit, so Claude can kill the hook before it gives up. Harmless: the watch ends the lease when `claude` exits.
- **A failed `claude plugin list`** still reads "Not installed" on the Settings page (doctor now skips).
- **On timeout, the runner doesn't kill grandchildren** (`ProcessRunner` has no process group).
- **The waiting picker** shows no selection for odd stored values (for example after `defaults write`).
- **`findClaude` and `runBounded` in the CLI are untested.**
- **A skill or hook change must bump the plugin version** (`plugin.json`) together with `MARKETING_VERSION`; the installed copy is cached by version, so otherwise it keeps the old files and Settings shows no "Needs update".

## Lid approvals (2c-1 leftovers)

- **Agent-granted mark survives menu changes.** If an agent's `on` got lid and you then change that session from the menu, it still counts as agent-granted, so switching to Never takes its lid. Fix: a counter bumped by the menu entry points, stored with the mark.
- **Under Never, an agent re-acquiring a person's named lease** drops that lease's lid.
- **The `claude-` session prefix** is duplicated in `GuardrailNotifier` and `RequestHandler.sessionLeasePrefix`.
- **No test for `AgentDetection.descends`** walking past 64 steps (the cycle case is tested).
- **Agent detection is advisory.** An agent escapes it by detaching itself (`(mooring on --level lid &)` reparents to `launchd`), by launching `mooring` through Terminal or `osascript`, or by naming a binary `claude` to inherit "Always allow Claude Code". It guards against accidents, not a hostile agent.
- **The first-run permission prompt runs outside the 60 s budget:** the timer starts after `authorize()` returns, so the first ask can outlast the CLI's 65 s ("didn't answer") and a later Allow still adds lid.
- **Which leases got lid on an agent's behalf** is kept in memory, so after a relaunch Never and session lid off don't take lid back from restored named leases (session leases lose it on their next hook event).
- **Authorized but alerts off** isn't treated as unavailable: the ask posts nothing visible and runs out its 60 s.
- **A failed notification post** (`center.add` throws) means a timeout instead of "unavailable".
- **An unwatched hook session under Always ask** can be falsely refused ("the request changed") when it renews during the ask, because "expiry no later" fails after a renewal.
- **Compare the whole watch** (pid and start time) when checking that the request is unchanged, not just the pid.
- **Under Never,** an agent's refused `on --level lid` downgrades a person's lid session.
- **Session acquires on battery** still log a guardrail notice (the notification is skipped).
- **The decision tests** are tables, not a full exhaustive product of every input.

## MCP, links and Shortcuts (2c-2 leftovers)

- `mooring --version` and MCP `serverInfo.version` report 0.2.0-dev while the app is 0.0.3; read the bundle version.

## CLI and IPC (stage 2a leftovers)

- **Re-acquire edge cases (from the 2b-prep fixes):**
  - re-acquiring a lease whose watched process just died fails with "Process N isn't running", even when only `--ttl` was given;
  - re-acquiring an expired, not-yet-ticked lease silently revives its old watch, level and reason;
  - a raw wire client can re-acquire a watched lease without `ttl` or `watchPid`, because the merged watch satisfies the policy check (the CLI blocks this);
  - a pre-`ttl` lease re-acquired with `--ttl 60` gets a 60 s renew length.
- **Connect failures from a full backlog** (`ECONNREFUSED` or `EAGAIN` at the 16-connection cap) still say "isn't running" rather than "didn't answer".
- **Small code and test leftovers:**
  - `Plan.reasonGiven` duplicates the handler's `cleaned(_:)`;
  - the `blocked` socket test returns early as root instead of using `.enabled(if:)`;
  - there's no test for `anchor -- cmd --json` keeping anchor's own errors human, or for the ttl after a longer re-acquire.

- **`on` can reply with an expired session.** With no flags, it can reply with a just-expired, not-yet-ticked menu lease, a window of up to 5 s. Filter with `isLive(at:)`.
- **SPEC 2.2's exit-2 wording** should say "held but paused by a guardrail", not "refused".
- **`doctor`:**
  - its "mismatch" fix text is wrong in one direction, and a transient mismatch can show during a helper call;
  - the Helper check fails for people who never use lid mode.
- **Settings and install:**
  - A regular file at `~/.local/bin/mooring` reads "Points to <own path>" in Settings; say "Not a link".
  - `make uninstall` doesn't remove the symlink, though SPEC's Repository setup says it does.
- **"End my session after the Mac sleeps"** now also ends a CLI `on`, which follows from the one-switch decision. Note it in the release notes.
- **A Terminal-started menu session** shows the reason "Turned on from the menu bar".
- **`anchor`:**
  - Hardening: a microsecond gap between spawn and forwarding (pre-install `SIG_IGN` plus `POSIX_SPAWN_SETSIGDEF`), and a pid-reuse window in `wait()`.
  - SIGQUIT isn't handled.
- **Robustness:**
  - The launch deadline uses the wall clock; use `ContinuousClock`.
  - Unknown client errors drop the underlying error.
  - `printJSON` returns 0 after an encode failure.
- **Display:**
  - `p_comm` truncates process names to 16 characters.
  - `status` columns count characters, not display width.
- **Socket server:**
  - `withDeadline`'s timer lives the full second on success.
  - There's no total per-connection deadline after the read.
  - `accept` spins on `EMFILE`.
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
- **`scripts/cli-smoke.sh`** has no cleanup trap.
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
- **VoiceOver:** hosted menu items have empty titles, so VoiceOver may read them as blank.
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

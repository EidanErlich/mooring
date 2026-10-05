# Stage 2c-2: MCP server, `mooring://` links and Shortcuts

Oct 3, 2026 · Eidan Erlich · Status: built (shipped in 0.1.0)

## Goal

Every way you or an agent might reach for "keep the Mac awake" ends in the same lease engine:

- **Agents without a shell** (Claude Desktop, Cursor chat, any MCP client) use `mooring mcp`.
- **Launchers and scripts** (Raycast, Alfred, bookmarks) use `mooring://` links.
- **Shortcuts, Siri and Spotlight** use App Intents.
- **Agents can tell you when they're done** with `notify`, from MCP or `mooring notify`.

This is the second half of SPEC.md stage 2c. 2c-1 (lid approvals) is merged, and everything here uses its rules for who counts as an agent and when lid mode asks.

## Decisions (2026-10-03)

| Question | Decision |
| --- | --- |
| Scope | **All four:** Shortcuts/Siri, `mooring://` links, MCP for other agents, and the `notify` tool. |
| How far a link is trusted | **Like an agent.** Links follow "Lid mode for agents"; Shortcuts are trusted like the menu. |
| Claude Code plugin and MCP | **No `.mcp.json`.** Claude Code keeps its hooks and skill, plus a new `mooring notify` command. |
| Connecting MCP clients | **Both:** one-click Add/Remove for Claude Desktop and Cursor, and a Copy config snippet for any client. |
| `MOORING_AGENT_LEVEL` | **Dropped.** 2c-1's "Keep working with the lid closed" already covers it for every project. |

## MCP server

### Transport and protocol

- `mooring mcp` speaks MCP over stdio: newline-delimited JSON-RPC 2.0 on stdin and stdout, with logs on stderr. It is hand-rolled inside MooringCLICore, with no new dependency.
- **It handles** `initialize`, `notifications/initialized`, `ping`, `tools/list` and `tools/call`.
  - Any other method gets JSON-RPC error `-32601`.
  - A malformed line gets `-32700`.
  - Notifications get no reply.
- **`initialize`:**
  - If the client's `protocolVersion` is one the server supports, the server replies with that version; otherwise it replies with its newest.
  - Supported versions are `2025-06-18`, `2025-03-26` and `2024-11-05`.
  - Capabilities: `{"tools": {}}`.
  - `serverInfo`: `{"name": "mooring", "version": <app version>}`.
  - The server keeps `clientInfo.name` as the client name.
- **Each tool call** is one socket request to the app, sent with the client name, or with an empty name before `initialize` gives one (the app shows that as "MCP client"), so a call before `initialize` is still an MCP client's. If the app isn't running, the server launches it, as the CLI does.
  - Socket and wire errors become tool results with `isError: true` and the CLI's message text, so the model can read them.
  - Protocol errors stay JSON-RPC errors.
- **The server exits on stdin EOF.** The client's leases watch the server's own pid (see below), so they end when the client disconnects.

### Who the client is

- **The app treats every MCP request as an agent request,** whatever the process ancestry. This closes the gap where an MCP server launched by Claude Desktop would count as a person under 2c-1's rules.
- **Display name:** a fixed table maps known `clientInfo.name` values to friendly names:
  - Claude Desktop's to "Claude Desktop";
  - Cursor's to "Cursor".

  The exact strings are recorded during implementation from a real `initialize`. Any other client shows its own name with control characters dropped, cut to 40 characters and trimmed, or "MCP client" when nothing is left or what is left reads "Terminal" (in any case), so a client can't pass for a person.
- **That name appears** on the menu row, in approval notifications, in "Always allow" and in `notify`.
- **Lease ids** are `mcp-<slug>-<n>`, where the slug is the lowercased client name with non-alphanumerics turned into `-`, at most 24 characters, and `n` counts up from 1 within one server process.

### Tools

The tool list is fixed at build time. A test asserts exactly these four names, and that no tool name or description mentions the clipboard.

| Tool | Arguments | Does |
| --- | --- | --- |
| `keep_awake` | `minutes` (integer 1–240, required), `reason` (string, optional), `level` (`system`, `display` or `lid`, default `system`), `lease_id` (optional, to extend one of this client's leases) | Creates `mcp-<slug>-<n>`, or renews the named lease, with expiry = now + minutes and a watch on the `mooring mcp` process. It always has an end, so lid needs no prompt under the default setting; under "Always ask" the call waits for the answer (up to 60 s). Every success returns the same `structuredContent`, `{lease_id, level, ends_at, guardrail?}`, with `guardrail` only when the guardrail holds the lease. |
| `release_awake` | `lease_id` (optional) | Releases that lease, or every lease this client created when none is given. It can't name another owner's lease, which gets "not one of this client's leases". |
| `awake_status` | none | Summary line, effective level, this client's leases (id, level, end), battery %, on AC, thermal state. |
| `notify` | `title` (required, ≤ 80 chars), `body` (optional, ≤ 300 chars) | Posts a macOS notification (see Notify). |

- **Argument checking happens in the server.** An out-of-range `minutes` or an unknown `level` is a tool error with a plain message, never a crash.
- **"This client's leases"** means `owner == .mcp(client:)` with this server's client name **and** a watch on this server's pid. So two Claude Desktop windows, each with its own server, can't release each other's leases.

## Notify

- **A new socket op, `notify`,** with args `{title, body?}`. The app posts a notification:
  - its title is "<Agent>: <title>", using the caller's agent name ("Claude Code", "Claude Desktop", …), or "Terminal" for a person;
  - its body is the body;
  - it uses no category, so it has no buttons.
- **Rate limit:** one per 30 s per caller name. A faster call gets `denied` with "Rate-limited: try again in N s". A last notification that seems to be in the future (the clock moved back) counts as expired, so a clock change never blocks a caller for longer than 30 s.
- **Setting:** Settings → Awake → Agents → **"Let agents post notifications"**, `AwakeSettings.agentNotifications: Bool = true`. When it's off, `notify` gets `denied` with "Notifications from agents are turned off in Settings". It applies to agent callers only; your own `mooring notify` always posts.
- **If notifications aren't allowed,** `notify` gets `denied` with "Turn on notifications for Mooring in System Settings". Lid approvals keep 2c-1's longer message, which ends "to approve lid mode".
- **The CLI:** `mooring notify "<title>" ["<body>"]` exits 0 when posted and 2 when denied.
- **The skill** gets one line: "When a long job finishes and the user may be away, `mooring notify "Done" "<what finished>"` tells them."

## `mooring://` links

- **Routes**, all acting on the menu session, the same one switch as `mooring on` and `off`:
  - `mooring://on`, with optional `for` (`90s`, `15m`, `2h`, `1h30m`), `level` (`system`, `display`, `lid` or `display,lid`) and `reason`. Missing values take `mooring on`'s defaults.
  - `mooring://off`.
  - `mooring://toggle`: off if the menu session is on; otherwise on, with the same parameters as `on`.
- **The caller** is the app that sent the open request. The app reads the sender's pid from the `kAEGetURL` Apple event (`keySenderPIDAttr`) and uses its localized application name, such as "Raycast". If there's no sender, it's "A link".
  - It is **always an agent** for the lid rules: `on?for=2h&level=lid` just works under the default; lid with no end posts "Raycast wants to keep your Mac awake with the lid closed"; and "Always allow" remembers "Raycast".
  - The wait happens in the background. The link returns immediately, and the session starts without lid until you answer, as for hooks under "Always ask".
- **Errors** have no reply channel, so they post a notification titled "Mooring couldn't use that link". Its body is one of:
  - "unknown action 'onn'";
  - "'for' must look like 30m or 1h30m";
  - "unknown level 'lidd'";
  - the refusal reason, e.g. "Lid mode not approved (lid mode for agents is set to Never)". In that case the rest of the request still applies, as in 2c-1.

  Errors are rate-limited to one per 10 s.
- **Links never open a window or bring Mooring to the front.**
- **Registered** through `CFBundleURLTypes` with the scheme `mooring`. Links arrive through a `kAEGetURL` Apple-event handler that `AppDelegate` installs in `applicationWillFinishLaunching`, not through `application(_:open:)`, because the handler needs the event's sender pid. A link that launches the app waits for the request handler. Parsing is a pure function, `MooringLink.parse(URL) -> Result<LinkAction, LinkError>`.

## Shortcuts (App Intents)

These are trusted like the menu: a person runs them. They live in the app target (`App/Intents/`), run in the background (`openAppWhenRun = false`), and call the same engine paths as the menu and `mooring on`/`off`.

| Intent | Parameters | Result |
| --- | --- | --- |
| **Keep Mac Awake** | Duration (optional; empty = until turned off), Level (optional: Normal / Keep display on / Keep awake with lid closed; empty keeps the running session's level, else the click level, as `mooring on` without `--level` does) | Turns the menu session on. Guardrails apply as usual, and a guardrail is reported in the dialog ("Lid mode waits for power"). |
| **Let Mac Sleep** | none | Ends the menu session. |
| **Get Awake Status** | none | Returns an `AwakeStatus` entity: `isOn`, `summary`, `level`, `endsAt` (optional), `batteryPercent`, `onPower`. The dialog shows the summary. |

- **`AppShortcutsProvider` phrases:**
  - "Keep my Mac awake with \(.applicationName)";
  - "Let my Mac sleep with \(.applicationName)";
  - "Is my Mac staying awake with \(.applicationName)".
- **An action that runs before the app has set itself up** (a Shortcut that launches Mooring) waits for the request handler: `IntentActions` owns the `HandlerGate` that the app hands its handler to, so an action never finds Mooring "not running".
- **Excluded:** clipboard intents (Part 4), and intents for named leases.

## Settings → Awake → Agents → "Other agents (MCP)"

A new section under Lid mode:

- **Rows for Claude Desktop and Cursor,** each showing its state and one button:

  | State | Meaning | Button |
  | --- | --- | --- |
  | **Not installed** | The client's config folder doesn't exist | none |
  | **Not added** | The client is installed but has no `mooring` entry | **Add** |
  | **Added** | `mcpServers.mooring.command` is this app's helper path | **Remove** |
  | **Needs update** | The entry points at a different or missing path | **Update** |

- **Config files:**
  - Claude Desktop: `~/Library/Application Support/Claude/claude_desktop_config.json`;
  - Cursor: `~/.cursor/mcp.json`.

  A missing file counts as `{}` when the folder exists.
- **Add** and **Update:**
  1. Read the file. If it isn't a JSON object, change nothing and show "<file> isn't valid JSON, so Mooring left it alone. Use Copy config instead."
  2. Copy the original to `<file>.mooring-backup`, overwriting any earlier backup.
  3. Set `mcpServers.mooring = {"command": "<this app>/Contents/Helpers/mooring", "args": ["mcp"]}` and keep every other key.
  4. Write the file atomically, pretty-printed with sorted keys. Key order may change, which the caption says.
  5. Show "Restart Claude Desktop to load it."

  A symlinked file is written through and stays a link. A dangling link (a dotfiles repo not checked out yet) is followed to where it points, read relative to the link's folder, and that file's folder is created if needed.
- **Remove** deletes `mcpServers.mooring` only, with the same backup, and drops an empty `mcpServers`.
- **Copy config** copies the snippet `{"mcpServers": {"mooring": {"command": "…", "args": ["mcp"]}}}`. A caption explains: "Paste into your MCP client's config. Most clients call this file mcp.json."
- **"Let agents post notifications"** (toggle, on) sits in this section.
- **The editor** is `MCPClientConfig`, a pure struct over a file URL with an injected file system, so tests run on temporary directories.

## `doctor`

A new check 8, **"MCP clients"**:
- ✓ "Claude Desktop, Cursor" (those with Added);
- – "none added";
- ✗ "Claude Desktop needs update", when an entry's command doesn't exist or isn't this app's, with the fix "Settings → Awake → Agents → Update".

The CLI reads the same two files with the same pure code, via MooringCLICore; the app isn't involved.

## Wire changes

- **`Op` gains `notify`** (`NotifyArgs {title, body?}`, `NotifyResult {posted: Bool}`).
- **`AcquireKind` gains `mcp`** (`AcquireArgs` with `client`, `minutes`, `level`, `reason` and optional `id`). **`ReleaseKind` gains `mcp`** (`client`, optional `id`). The handler builds the id, the expiry and the watch on the caller's pid. `CallerPolicy` caps `minutes` at 240.
- **`StatusArgs` gains an optional `client`.** With it, `status` lists only that client's leases (for `awake_status`).
- **All additions decode leniently.** Older CLIs never send them, and the protocol stays `v: 1`.

## Components

| Piece | Where | Does |
| --- | --- | --- |
| `MCPServer` | MooringCLICore | The stdio loop, JSON-RPC framing, `initialize` negotiation, the tool table, argument checks and the relay to the socket. Built from pure parts: `MCPMessage` (decode/encode) and `MCPTools` (call → `Request`). |
| `mooring mcp`, `mooring notify` | MooringCLICore `Commands.swift` | The new subcommands. |
| `MCPClientName` | MooringIPC | Maps `clientInfo.name` to the display name and slug. |
| Handler: `notify`, `mcp` acquire/release, client status | `App/IPC/RequestHandler+MCP.swift`, `+Notify.swift` | MCP requests are always agent requests; rate limit; setting; posting through the existing `NotificationPosting`. |
| `MooringLink` | App, pure | Parses URLs into `LinkAction`. |
| `LinkHandler` | App | Sender-app lookup, the in-app call into the handler as an agent named after the sender, and error notifications. |
| Intents | `App/Intents/` | Three intents, `AwakeStatus` entity and `MooringShortcuts` provider. |
| `MCPClientConfig` | MooringIPC (shared by the app and `doctor`) | Reads and writes client configs, and reports their state. |
| Settings section | `AgentsSettingsPage` | The "Other agents (MCP)" section and the notify toggle. |

## Testing

- **`MCPServerTests`** drive the server over an in-memory pipe against a fake socket client:
  - the `initialize` handshake, version echo and fallback;
  - notifications get no reply;
  - unknown method → `-32601`;
  - a bad line → `-32700`;
  - `tools/list` is exactly the four tools and mentions no clipboard;
  - each tool builds the right `Request`;
  - out-of-range or unknown arguments → `isError`;
  - a `denied` wire error → `isError` with its message;
  - EOF ends the loop.
- **`MCPClientNameTests`:** known names, unknown names, empty names, slugging and the length limit.
- **Handler:**
  - an MCP acquire from a "person" ancestry is still treated as an agent;
  - `keep_awake` lid under the default setting is granted with no prompt;
  - under "Always ask", it asks;
  - releasing another client's lease → `notFound`;
  - `notify` rate limit, setting off, notifications denied, and the title prefix.
- **`MooringLinkTests`:** every route and parameter, bad durations, bad levels, unknown actions, `toggle` both ways.
- **`LinkHandlerTests`:**
  - the sender's name becomes the agent;
  - no sender → "A link";
  - open-ended lid asks;
  - Never → error notification and session without lid;
  - error notifications are rate-limited.
- **Intents:** each intent's `perform` is tested against an injected engine and handler, along with the status entity's fields.
- **`MCPClientConfigTests`**, on temporary directories:
  - a missing folder → Not installed;
  - a missing file → Not added;
  - Add keeps other servers and writes the backup;
  - invalid JSON is left untouched;
  - Remove drops only `mooring` (and an empty `mcpServers`);
  - an old path → Needs update.
- **CLI:** `mooring notify` exits 0 or 2. `doctor` check 8 covers its three states.

## Manual check

1. **Shortcuts:** run "Keep Mac Awake" for 30 min. The menu shows it. "Get Awake Status" reports on, with the summary.
2. **Raycast:**
   - Open `mooring://on?for=1h&level=lid`. Lid mode turns on with no prompt.
   - Then `mooring://off`, then `mooring://on?level=lid`. A "Raycast wants…" notification appears.
   - Open `mooring://onn`. The error notification appears.
3. **Claude Desktop:**
   - In Settings → Awake → Agents, click **Add** for Claude Desktop and restart it.
   - Ask it to keep the Mac awake for 20 minutes. "Claude Desktop" appears in the menu.
   - Ask it to tell you when it's done. A notification arrives.
4. **Claude Code:** ask it to run `mooring notify "Test" "from Claude Code"`.
5. **`mooring doctor`** shows "MCP clients ✓ Claude Desktop".

## SPEC.md changes

- **2.2:** `mooring notify`, and `mooring mcp` marked as shipped. The "Other entry points" paragraph becomes a pointer to the new sections.
- **2.5 MCP server:**
  - the tool table above, replacing the old one (`keep_awake` gains `lease_id` and `display`; `notify` is limited per caller);
  - MCP requests are always agent requests;
  - client names and slugs;
  - leases watch the server process.
- **New sections** for links, Shortcuts, and "Other agents (MCP)" in Settings.
- **2.3:** remove the `.mcp.json` sentence and the `MOORING_AGENT_LEVEL` line.
- **Agent control and approvals:** links and MCP clients are agents named after the sender or client.
- **Engineering decisions:** the wire additions; MCP is hand-rolled; the supported protocol versions.
- **Stage table:** the 2c-2 row matches this scope.

## Out of scope

- MCP over HTTP or SSE; resources and prompts; MCP window tools (stage 3).
- One-click setup for clients other than Claude Desktop and Cursor (Copy config covers them).
- Clipboard anything (Part 4).
- A global hotkey (Shortcuts page, stage 3.5).

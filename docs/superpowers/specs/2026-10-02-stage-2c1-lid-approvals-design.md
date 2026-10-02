# Stage 2c-1: lid mode for agents, with approvals

Oct 2, 2026 · Eidan Erlich · Status: design approved in conversation; spec awaiting owner review

## Goal

An agent can keep the Mac awake **with the lid closed**. Close the lid while Claude works, and it keeps working.

Lid mode for work that has an end needs no prompt. That covers work tied to a process, a chat session or a time limit. Lid mode with **no end** asks first by default, because a laptop left awake with the lid shut and nothing to stop it is how a battery gets drained by accident. How much you're asked is configurable. Commands you type in your own Terminal stay trusted, like the menu.

This is the first half of SPEC.md stage 2c. The second half, 2c-2 (`mooring mcp`, the `mooring://` URL scheme and App Intents), gets its own spec.

## Owner decisions (2026-10-02)

| Question | Decision |
| --- | --- |
| How 2c is split | **Two parts:** 2c-1 is lid approvals (this spec); 2c-2 is MCP, the URL scheme and App Intents. |
| What asks by default | **Only open-ended agent lid requests.** Agents can freely tie lid mode to processes and chats. The human in the loop is configurable. |
| Claude Code sessions | **"Keep working with the lid closed"**, on by default. Session leases use lid level while Claude works. They're tied to the chat, so they need no approval. |
| What "Always allow" remembers | **That agent only**, e.g. "Always allow Claude Code". It's listed and removable in Settings. |
| Your own Terminal | **Trusted**, like the menu, under every setting. |

## Who counts as an agent

- **Detection happens in the app,** from the caller's pid (`LOCAL_PEERPID`). The app walks the process ancestry (at most 64 steps, stopping at pid 1) through the same sysctl process table the CLI uses.
- **A request is an agent request** if any ancestor's name is one of `claude`, `codex`, `cursor-agent`, `gemini`, `aider` or `opencode`. The agent's display name is "Claude Code", "Codex" and so on, otherwise the process name.
- **Every `op: hook` request is an agent request** (Claude Code).
- **Anything else is a person:** your Terminal, `launchd`, Raycast, scripts you start yourself. People are never asked; lid mode follows today's rules for them.

## The decision

**An open-ended request** asks for a lease with **no expiry and no watched process**. For agents that's essentially `mooring on --level lid` without `--for`, when the click default is "until turned off". `anchor`, `lease` and session leases always have an end.

**The setting:** "Lid mode for agents", a new key, `AwakeSettings.agentLidApproval: AgentLidApproval`, defaulting to `.askWhenOpenEnded`. The old `agentLid` key is never shown or used. No screen ever set it, so its stored default isn't a user choice.

| Setting | Agent request with an end | Agent request with no end |
| --- | --- | --- |
| **Ask only when it has no end** (default) | allow | ask, unless the agent is always-allowed |
| Always ask | ask, unless the agent is always-allowed | ask, unless the agent is always-allowed |
| Always allow | allow | allow |
| Never | refuse | refuse (even for always-allowed agents) |

- **Pure function:** `LidApproval.decide(setting:, isAgent:, hasEnd:, agentName:, alwaysAllowed:) -> .allow | .ask | .refuse`, in AwakeKit. Non-agents always get `.allow`.
- **Refuse, deny or timeout:** the lease is still created or updated, but at the requested level **without lid**. The reply is `denied` (exit 2) with the reason:
  - "Lid mode not approved (denied)";
  - "… (no answer in 60 s)";
  - "… (lid mode for agents is set to Never)";
  - "Turn on notifications for Mooring in System Settings to approve lid mode".
- **After approval,** the battery guardrails apply as today: lid mode needs AC until the opt-in, pauses below 20%, and everything pauses below 10%.
- **Policy changes from stage 2a:**
  - `CallerPolicy` no longer refuses lid for named leases outright; `LidApproval` decides. Under the default, named leases with lid are allowed, since they always have an end.
  - Unchanged: the 4 h cap, the 32-lease limit, reserved ids and the other rules.

## Claude Code sessions

- **Settings → Awake → Agents → "Keep working with the lid closed"** is `AwakeSettings.agentSessionLid: Bool = true`. When it's on, the `claude-<session>` lease is acquired and renewed at lid level, `AwakeLevel(display: false, lid: true)`; when it's off, at system level.
- **Session leases have an end,** so they're allowed by default. Under "Always ask", a hook can't wait (Claude gives it 2 s), so the lease starts at system level, a notification is posted, and Allow upgrades the lease to lid. Under "Never", sessions stay at system level.
- **The lease lifecycle from 2b is unchanged.**

## Asking

- **The notification** uses `UNUserNotificationCenter`, with category `mooring.lid-approval` and three actions:
  - title: "<Agent> wants to keep your Mac awake with the lid closed";
  - body: "<reason> · <with no end time | for 30m | while <process> runs>";
  - actions: **Allow once**, **Always allow <Agent>** and **Deny**;
  - the request id goes in `userInfo`.
- **Clicking the notification body** opens Settings → Agents and counts as no answer.
- **Permission:** requested the first time an approval is needed. If it's denied or off, the request is refused immediately with the notifications message.
- **Waiting:**
  - The request handler awaits the decision for up to 60 s.
  - Socket connections are independent, so other requests aren't blocked.
  - Two pending requests show two notifications.
  - The CLI's reply timeout is 65 s for any request that asks for lid level (`--level lid` on `on`, `anchor` or `lease acquire`), and 5 s otherwise.
  - SPEC.md already reserves the op name `approve.wait`. It isn't needed as a separate op, because the acquire itself waits. The name stays reserved.
- **"Always allow <Agent>"** appends the agent name to `AwakeSettings.agentLidAlwaysAllowed: [String]`.
- **Pending state:** while a lease waits, its row and `mooring status` show "waiting for your approval". `LeaseInfo` gains `pendingApproval: Bool`. The menu shows the same in the Anchored row.

## Settings → Awake → Agents

A new **"Lid mode"** section:

- **"Keep working with the lid closed"** (toggle, on), with the caption "Claude Code sessions keep the Mac awake with the lid closed while they work."
- **"Lid mode for agents":** Ask only when it has no end / Always ask / Always allow / Never.
- **"Always allowed":** the list of agent names, each with Remove; hidden when empty.
- **Caption:** "Battery guardrails always apply: lid mode needs power until you allow it on battery, and pauses when the battery is low."

## `doctor`

A new **"Notifications"** check, check 7:

- ✓ "allowed";
- – "not asked yet";
- ✗ "denied", with the fix "System Settings → Notifications → Mooring", **only** when the lid setting could need to ask (anything except Always allow and Never). Otherwise – "denied (not needed)".

The app reports `notifications: "allowed" | "notDetermined" | "denied"` in `StatusResult`.

## Skill

One line is added to `skills/mooring/SKILL.md`: "To keep the Mac awake with the lid closed, prefer a hold, `mooring lease acquire job-<slug> --level lid --watch-pid auto`, which needs no approval. `mooring on --level lid` with no end time asks the user first and may be declined (exit 2)."

## Components

| Piece | Where | Does |
| --- | --- | --- |
| `LidApproval` | AwakeKit, pure | The table above. |
| `AgentLidApproval`, plus `agentLidApproval`, `agentSessionLid` and `agentLidAlwaysAllowed` | AwakeKit `AwakeSettings` | New keys, with fallbacks when decoding older settings. |
| `AgentDetector` | App (sysctl process table), pure core with an injected table | Peer pid → agent name or nil. |
| `LidApprover` | App, `@MainActor` | Posts the notification and awaits its action, with a 60 s limit. A protocol, so tests inject allow, deny, timeout or unavailable. |
| Request handler changes | `App/IPC/RequestHandler*.swift` | Classify the caller; for lid requests call `LidApproval`, then the approver; fall back to no-lid; mark pending; session lid level from the setting; hook upgrade on approval. |
| Wire changes | MooringIPC | `LeaseInfo.pendingApproval` and `StatusResult.notifications` (both decode leniently). |
| CLI | MooringCLICore | 65 s reply timeout for lid requests; "waiting for your approval" in `status`; doctor check 7. |
| Settings page | `AgentsSettingsPage` | The Lid mode section. |
| Menu | `LeaseRow` | "waiting for your approval". |

## Testing

- **`LidApprovalTests`:** every setting × with an end / no end × always-allowed or not × agent or person. "Never" beats always-allowed, and people always get allow.
- **`AgentDetectorTests`:**
  - `zsh → claude` is Claude Code;
  - `zsh → login → Terminal` is a person;
  - `codex` is detected;
  - a loop or deep chain stops at 64 steps;
  - a missing pid counts as a person.
- **Request handler**, with an injected approver and detector:
  - a person's `on --level lid` gives lid with no prompt;
  - an agent's open-ended `on --level lid`: Allow gives lid; Deny gives system and `denied`; timeout gives system and `denied` "no answer"; unavailable gives the notifications message;
  - "Always allow" persists, and the next request skips the ask;
  - a named lease at lid with an end is allowed;
  - "Never" refuses;
  - session lid follows the switch;
  - a hook under "Always ask" starts at system level and upgrades on Allow;
  - `pendingApproval` is true while the ask is pending.
- **The notification:** a test maps action identifiers to decisions.
- **CLI:** the 65 s timeout applies only to lid requests; `denied` exits 2 with the message; `status` shows the pending text; doctor check 7 covers its cases.
- **Settings:** older settings decode to the defaults, and the new keys round-trip.

## Owner check

1. On AC, start a Claude task and close the lid. Claude keeps working, and the LID tag shows.
2. Ask Claude to run `mooring lease acquire job-x --level lid --ttl 30m --watch-pid auto`. No prompt.
3. Ask Claude to run `mooring on --level lid`. The notification appears.
   1. Deny: exit 2, and the session stays at system level.
   2. Repeat with **Always allow Claude Code**: it goes through, and "Claude Code" appears under Always allowed.
4. Set "Lid mode for agents" to Never. Agent lid requests stay at system level.
5. Run `mooring on --level lid` yourself in Terminal. No prompt, under any setting.

## SPEC.md changes

- **Agent control and approvals:** the new four-option table (default "Ask only when it has no end"), session lid, "Always allow <Agent>", and agent detection by process ancestry.
- **2.6 policy table:** lid for named leases is decided by `LidApproval`, no longer `denied`.
- **2.3:** session leases use lid while "Keep working with the lid closed" is on.
- **Engineering decisions:**
  - the new settings keys;
  - `approve.wait` stays reserved but unused;
  - `pendingApproval` and `notifications` on the wire.
- **Stages:** split row 2c into 2c-1 and 2c-2.

## Out of scope

- `mooring mcp`, the `mooring://` URL scheme and App Intents (2c-2).
- Push notifications to a phone (2.7).
- Window-arrangement approvals (stage 3).

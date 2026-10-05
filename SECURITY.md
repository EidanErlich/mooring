# Security

## Reporting a vulnerability

Please report security issues privately, through GitHub's private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability**. Don't open a public issue for a security problem.

Include what you found, the Mooring version (`mooring --version`), your macOS version, and steps to reproduce. Reports are answered as soon as possible; please allow some time for a fix before disclosing it.

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |
| Older builds | No; update first |

## Threat model, in short

Mooring runs as you, plus one small root helper. What it defends, and what it doesn't:

- **The root helper** (`dev.mooring.helper`, a launchd daemon you approve once) does one thing: it runs `/usr/bin/pmset -a disablesleep 0` or `1` with a fixed argument list, and reads `pmset -g`. No string from a caller reaches a shell. It accepts XPC connections only from the Mooring app signed with the same certificate (a code-signing requirement on the app's identifier and its certificate's hash, checked by the system before the helper's code runs), and refuses every connection when built without a real signature. If the app quits, crashes or stops sending its heartbeat, the helper turns lid sleep back on by itself. The source is in `Helper/` and is kept under 250 lines with no dependencies.
- **The `mooring` command** talks to the app over a Unix socket in `~/Library/Application Support/Mooring/` (socket mode 0600, folder 0700). The app also checks that the peer runs as your user. Anything that runs as you can use it; nothing else can.
- **Agents.** Requests whose process ancestry includes a known coding agent, `mooring mcp` (MCP clients) and `mooring://` links all count as agents: open-ended lid mode, window arrangement and notifications follow the policies in Settings → Awake → Agents, which can ask you first or refuse. **Agent detection is advisory**: it guards against accidents, not against a hostile agent, which can escape it by detaching itself or launching `mooring` some other way (see `docs/BACKLOG.md`). Don't rely on it as a sandbox.
- **Clipboard history** (off by default) is stored unencrypted in `~/Library/Application Support/Mooring/Clipboard/`, in a folder only you can open. No command, MCP tool, link, Shortcuts action or AppleScript call returns it, but any process running as you, including an agent with shell access, can read the file. Leave Clipboard off if that matters to you.
- **Updates** use Sparkle with EdDSA-signed updates (Sparkle verifies each update archive), and only on builds with an update key after you opt in. Mooring makes no other network requests.

Out of scope: anything that already runs as root, or that can change your login keychain or System Settings approvals.

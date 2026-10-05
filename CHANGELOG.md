# Changelog

## 0.1.0 (unreleased)

The first release.

- **Keep awake from the menu bar.** Left-click the anchor to turn it on with your defaults; right-click for durations, "until I open the lid", "while an app is running" and keeping the screen on. Everything that keeps the Mac awake is a lease in one engine, listed in the menu with who holds it and why, and each can be ended on its own.
- **Lid mode.** Keep the Mac running with the lid closed, with no password after you approve Mooring's helper once. The helper only runs `pmset -a disablesleep 0|1` for the signed Mooring app, and turns lid sleep back on within seconds if Mooring quits or crashes (within 90 s if it hangs). Lid mode pauses on low battery or when the Mac runs hot, and running on battery needs an explicit opt-in.
- **The `mooring` command.** `on`, `off`, `anchor -- <command>`, named leases (`lease acquire`, `release`, `--watch-pid auto` for agents), `status`, `doctor`, `notify` and `win`, over a user-only socket. Settings → General installs it at `~/.local/bin/mooring`.
- **Claude Code plugin.** Hooks keep the Mac awake while Claude works and let it sleep about two minutes after Claude stops, including background tasks, permission prompts and subagents. A skill teaches Claude the hold and `anchor` patterns. Install it from Settings → Awake → Agents or from this repo's marketplace.
- **Agent approvals.** Lid mode asked for by an agent can need your OK (Allow once, Always allow, Deny) in a notification; Settings → Agents sets the policy for lid mode, windows and notifications.
- **MCP, links and Shortcuts.** `mooring mcp` gives Claude Desktop, Cursor and other MCP clients `keep_awake`, `release_awake`, `awake_status`, `notify` and five window tools, with Add, Update and Remove for Claude Desktop and Cursor in Settings. `mooring://on`, `off` and `toggle` links work from Raycast, Alfred and scripts, and Shortcuts gets "Keep Mac Awake", "Let Mac Sleep" and "Get Awake Status".
- **Windows (from Loop).** Loop's window manager runs inside Mooring, off by default: the radial menu on the fn key, keyboard actions and cycles, drag-to-edge snapping and the preview, with its settings under Settings → Windows. Agents can list, arrange, undo and save window layouts with `mooring win` or MCP.
- **Clipboard (from Maccy).** Maccy's clipboard history, off by default, with the ⇧⌘C popup, search, pins and paste. Password-manager and other concealed copies are never recorded, and no agent route can read the history.
- **Updates.** An opt-in Sparkle updater with EdDSA-signed updates, present only in builds with an update key. Builds without one make no network requests.
- **Uninstall.** Settings → Mooring → Advanced → Uninstall Mooring… turns lid sleep back on and removes the helper, login item, command, plugin, MCP entries, saved data and settings, then moves the app to the Trash.
- **Acknowledgements.** The license and every third-party notice ship inside the app, and Settings → Mooring → Advanced opens them.

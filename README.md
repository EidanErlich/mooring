# Mooring

Mooring is a free, open-source macOS menu-bar app that keeps your Mac awake, including with the lid closed, without a password prompt after a one-time approval. Scripts and coding agents drive the same engine through a `mooring` command.

> **Status:** early development. Mooring keeps your Mac awake (idle and display sleep) from the menu bar: left-click the anchor to turn it on, right-click for durations, "while an app runs" and the list of what's keeping the Mac awake. Lid mode (keep running with the lid closed) works after a one-time approval of Mooring's helper; it pauses itself on low battery or when the Mac runs hot, and if Mooring quits or crashes the helper turns lid sleep back on within a few seconds. The full design is in [docs/SPEC.md](docs/SPEC.md).

## Build from source

You need macOS 14 or later, Xcode, and [Homebrew](https://brew.sh).

```sh
make bootstrap   # installs XcodeGen and SwiftLint, generates Mooring.xcodeproj
make run         # Debug build, then launches the app; look for the anchor in the menu bar
make test        # unit tests for every package and the app
```

Builds are ad-hoc signed by default. Lid mode needs a build signed with your own Apple Development certificate (copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and fill it in), plus a one-time approval of Mooring in System Settings → General → Login Items & Extensions. The helper keeps running across rebuilds; after changing helper code, restart it with `sudo launchctl kickstart -k system/dev.mooring.helper`.

Other commands:

| Command | Does |
| --- | --- |
| `make build` | Debug build |
| `make lint` | SwiftLint |
| `make install` | Release build to `/Applications` |
| `make uninstall` | Quits Mooring and removes it from `/Applications` |
| `make reset-sleep` | Runs `sudo pmset -a disablesleep 0`, in case sleep is ever left disabled |
| `make clean` | Removes build output and the generated project |

## Use from Raycast, Shortcuts and MCP clients

Everything below ends in the same lease engine as the menu and the `mooring` command.

- **Raycast, Alfred and scripts:** open `mooring://on?for=1h&level=lid`, `mooring://off` or `mooring://toggle`. `for` takes `90s`, `15m`, `2h` or `1h30m`; `level` is `system`, `display`, `lid` or `display,lid`. A link counts as an agent, named after the app that sent it, so a lid link with no end asks first. Mistakes show up as a notification.
- **Shortcuts, Siri and Spotlight:** "Keep Mac Awake" (an empty Duration means until turned off), "Let Mac Sleep" and "Get Awake Status".
- **Claude Desktop, Cursor and other MCP clients:** in Settings → Agents → Other agents (MCP), click Add for Claude Desktop or Cursor and restart it; for any other client, click Copy config and paste it into the client's `mcp.json`. The server offers `keep_awake`, `release_awake`, `awake_status` and `notify`. `mooring doctor` checks the setup.
- **Telling you a job is done:** `mooring notify "Done" "what finished"`, or the MCP `notify` tool. Settings → Agents → "Let agents post notifications" turns it off for agents.

## Windows

Mooring also includes a window manager, [Loop](https://github.com/MrKai77/Loop), vendored as WindowKit: a radial menu, keyboard actions, cycles, drag-to-edge snapping and a preview. It is off by default and Mooring never asks for Accessibility until you turn it on. Choose **Windows › Turn On…** in the menu (or use the Window Manager switch in Settings → Windows → Behavior); Mooring explains what macOS calls Accessibility and opens System Settings → Privacy & Security → Accessibility, and Windows switches on by itself once you grant it. If you later revoke it, Windows turns itself off and the icon shows an orange "!" that reads "Windows needs Accessibility". The Windows settings are in Settings → Windows, and General → Shortcuts lists every global shortcut and flags clashes with each other and with macOS.

### Agents can arrange windows

With Windows on, an agent can move and resize your windows from a plain request ("Chrome on the right half, iTerm bottom left"). `mooring win list` shows the windows, `mooring win arrange chrome=right-half iterm=bottom-left` places them in one go, and `mooring win undo` puts them back; the Claude Code plugin and the MCP tools (`list_windows`, `arrange_windows`, `undo_arrangement`, `save_layout`, `apply_layout`) do the same. `mooring win layout save coding` keeps an arrangement to apply later. Settings → Agents → "Window arrangement by agents" chooses Automatic, Ask first (a notification with Allow and Deny) or Off.

## License

GPL-3.0-only; see [LICENSE](LICENSE). Code adapted from MIT-licensed projects keeps its original notices; see [THIRD_PARTY](THIRD_PARTY).

## Credits

Mooring builds on four open-source projects:

- [Awayke](https://github.com/daemonphantom/Awayke) (MIT): lid-closed mode and the privileged helper
- [Chai](https://github.com/lvillani/chai) (GPL-3.0): one-click idle and display sleep prevention with durations, reimplemented rather than copied
- [Loop](https://github.com/MrKai77/Loop) (GPL-3.0): window management
- [Maccy](https://github.com/p0deje/Maccy) (MIT): clipboard history and the floating panel

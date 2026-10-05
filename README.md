# Mooring

Mooring is a free, open-source macOS menu-bar app that keeps your Mac awake, including with the lid closed, without a password prompt after a one-time approval. Scripts and coding agents drive the same engine through a `mooring` command.

> **Status:** 0.1.0, not yet published as a release. Mooring keeps your Mac awake (idle and display sleep) from the menu bar: left-click the anchor to turn it on, right-click for durations, "while an app runs" and the list of what's keeping the Mac awake. Lid mode (keep running with the lid closed) works after a one-time approval of Mooring's helper; it pauses itself on low battery or when the Mac runs hot, and if Mooring quits or crashes the helper turns lid sleep back on within a few seconds. Two optional modules, both off until you turn them on, are built in: Windows, a window manager agents can drive, and Clipboard, a clipboard history agents can't read. The full design is in [docs/SPEC.md](docs/SPEC.md).

## Install

Mooring needs macOS 14 or later. There is no paid Apple account behind it, so the prebuilt download is not notarized (see the second option).

### Build from source (recommended)

You need Xcode and [Homebrew](https://brew.sh).

```sh
git clone https://github.com/EidanErlich/mooring.git && cd mooring
make bootstrap   # installs XcodeGen and SwiftLint, generates Mooring.xcodeproj
make install     # Release build to /Applications
```

An app you build yourself isn't quarantined, so macOS never warns about it. To update later, run `git pull && make install`.

### Signing and lid mode

Lid mode runs through a small root helper that only accepts the app signed with the same certificate, so it needs a build with a stable signature. A free Apple ID's personal team is enough: sign in to Xcode with your Apple ID once, then, before `make install`, copy [`Config/Local.xcconfig.example`](Config/Local.xcconfig.example) to `Config/Local.xcconfig` and fill in your identity and Team ID (the file says how to find both). Without it the build is ad-hoc signed, and everything but lid mode works. The first time you turn lid mode on, approve Mooring once in System Settings → General → Login Items & Extensions.

### Prebuilt download

Once 0.1.0 is published, download `Mooring-<version>.zip` from [GitHub Releases](https://github.com/EidanErlich/mooring/releases), unzip it and drag `Mooring.app` to `/Applications`. Mooring is signed with the maintainer's own certificate, not notarized, so macOS blocks the first open. Either:

- open System Settings → Privacy & Security and click **Open Anyway**, or
- run `xattr -dr com.apple.quarantine /Applications/Mooring.app` in Terminal.

### Homebrew

Once the tap is published:

```sh
brew install --cask eidanerlich/tap/mooring
```

The cask lives in a project tap (`EidanErlich/homebrew-tap`), because official Homebrew casks reject apps that aren't notarized. It prints the same quarantine advice after installing. Mooring updates itself, so `brew upgrade` leaves it alone (`auto_updates`); `brew uninstall` quits it first, and `brew uninstall --zap` also removes its Application Support folder and preferences.

## Getting started

Mooring lives in the menu bar: left-click the anchor to turn keep-awake on with your defaults, right-click for durations, lid mode and what's keeping the Mac awake.

**The `mooring` command.** Settings → General → **Install command-line tool** links `~/.local/bin/mooring` to the copy inside the app (add `~/.local/bin` to your `PATH` if it isn't there). A few examples:

```sh
mooring on --for 2h                       # keep the Mac awake for two hours
mooring anchor -- make build              # stay awake exactly as long as the build runs
mooring status                            # what's keeping the Mac awake, and why
mooring win do right-half --app Safari    # move a window (needs Windows on)
mooring doctor                            # check that the app, the command and the plugin are set up
```

`mooring --help` lists everything, and `mooring help <command>` explains one.

**The Claude Code plugin.** With it, every Claude Code session keeps the Mac awake while Claude works and lets it sleep once Claude stops. Install it from Settings → Awake → Agents → **Install**, which uses the copy bundled with the app so its version always matches, or from GitHub inside Claude Code:

```
/plugin marketplace add EidanErlich/mooring
/plugin install mooring@mooring
```

Restart running Claude Code sessions afterwards.

### Keyboard shortcuts

- **⇧⌘C** opens the clipboard popup (with Clipboard on).
- **Hold fn (🌐)** for the windows radial menu (with Windows on). While holding it, press an arrow key for that half (press it again to cycle to a third, then two thirds), two arrows for a quarter, **Space** to maximize or **Return** to center.

Settings → General → Shortcuts lists every global shortcut and flags clashes; Settings → Windows → Keybinds changes the window keys.

## Updates

Mooring makes no network requests of its own on a build without an update key, and the Updates settings don't appear. A release build with Sparkle's public key (`MOORING_SPARKLE_PUBLIC_KEY` in `Config/Local.xcconfig`) asks once, on first launch, whether to check for updates automatically; **Not Now** leaves checks off. Settings → Mooring → Advanced then has **Check for updates automatically** and **Check Now**. The updates come from `https://eidanerlich.github.io/mooring/appcast.xml` (live once 0.1.0 is published) and are verified with an EdDSA signature (Sparkle 2.10.0). When an automatic check finds an update while you're working in another app, Mooring doesn't pop a window up behind it: it posts a notification and adds **Update Available…** to the menu, which shows the update. If you built from source, update with `git pull && make install` instead.

## Uninstall

Settings → Mooring → Advanced → **Uninstall Mooring…** lists what it will do, then, in order:

1. ends every keep-awake session, so the Mac sleeps normally again;
2. turns lid sleep back on;
3. removes Mooring's helper;
4. stops Mooring opening at login;
5. removes the `mooring` command from `~/.local/bin`, if it links to this app;
6. removes the Claude Code plugin that came with the app;
7. removes Mooring from Claude Desktop and Cursor;
8. deletes clipboard history, only if you tick **Also delete clipboard history** (off by default);
9. deletes saved sessions (`leases.json`), saved window layouts (`layouts.json`) and the CLI socket (`mooring.sock`) from `~/Library/Application Support/Mooring`, and that folder too if nothing else is left in it;
10. deletes Mooring's settings (again as it quits, so nothing written on the way out survives);
11. moves Mooring to the Trash, then quits.

A step that fails doesn't stop the rest; Mooring lists what didn't finish before it quits. If lid sleep couldn't be turned back on, the list says to run `sudo pmset -a disablesleep 0` in Terminal. If the app is already gone, `make uninstall` quits Mooring, removes `~/.local/bin/mooring` when it links into `/Applications/Mooring.app`, and removes the app. It doesn't touch the helper, login item or settings, so use the in-app button first when you can.

## Privacy

- **No telemetry.** Mooring collects nothing and sends nothing about you or your Mac.
- **No network** unless the build has an update key and you opt in to update checks (automatic checks, or **Check Now**); then it fetches only the appcast and the update itself. A build without the key, which is any build from source unless you add one, never touches the network.
- **Clipboard history stays on your Mac**, in `~/Library/Application Support/Mooring/Clipboard/`: a folder only you can open (mode 0700), left out of backups, and **not encrypted**. Copies from password managers and other concealed copies are never recorded. Clipboard is off until you turn it on.
- **Agents can't read the clipboard history**: no command, MCP tool, link, Shortcuts action or AppleScript call returns it (see [Clipboard](#clipboard)).
- Logs go to the macOS unified log (subsystem `dev.mooring`) and never contain clipboard contents.

Security issues: see [SECURITY.md](SECURITY.md).

## Develop

You need Xcode and [Homebrew](https://brew.sh).

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
| `make uninstall` | Quits Mooring, removes `~/.local/bin/mooring` if it links into the installed app, and removes the app from `/Applications` |
| `make release` | Builds `dist/` (zip, appcast, Homebrew cask) for a release; publishes nothing. See [docs/RELEASING.md](docs/RELEASING.md) |
| `make reset-sleep` | Runs `sudo pmset -a disablesleep 0`, in case sleep is ever left disabled |
| `make clean` | Removes build output and the generated project |

[CONTRIBUTING.md](CONTRIBUTING.md) covers signing, the vendoring rules and the commit style.

## Releasing

The maintainer's step-by-step checklist (Sparkle keys, the version, `scripts/release.sh`, the Homebrew tap, GitHub Pages and the tag) is in [docs/RELEASING.md](docs/RELEASING.md). Nothing is published automatically.

## Use from Raycast, Shortcuts and MCP clients

Everything below ends in the same lease engine as the menu and the `mooring` command.

- **Raycast, Alfred and scripts:** open `mooring://on?for=1h&level=lid`, `mooring://off` or `mooring://toggle`. `for` takes `90s`, `15m`, `2h` or `1h30m`; `level` is `system`, `display`, `lid` or `display,lid`. A link counts as an agent, named after the app that sent it, so a lid link with no end asks first. Mistakes show up as a notification.
- **Shortcuts, Siri and Spotlight:** "Keep Mac Awake" (an empty Duration means until turned off), "Let Mac Sleep" and "Get Awake Status".
- **Claude Desktop, Cursor and other MCP clients:** in Settings → Agents → Other agents (MCP), click Add for Claude Desktop or Cursor and restart it; for any other client, click Copy config and paste it into the client's `mcp.json`. The server offers `keep_awake`, `release_awake`, `awake_status`, `notify`, and the window tools `list_windows`, `arrange_windows`, `undo_arrangement`, `save_layout` and `apply_layout`. `mooring doctor` checks the setup.
- **Telling you a job is done:** `mooring notify "Done" "what finished"`, or the MCP `notify` tool. Settings → Agents → "Let agents post notifications" turns it off for agents.

## Windows

Mooring also includes a window manager, [Loop](https://github.com/MrKai77/Loop), vendored as WindowKit: a radial menu, keyboard actions, cycles, drag-to-edge snapping and a preview. It is off by default and Mooring never asks for Accessibility until you turn it on. Choose **Windows › Turn On…** in the menu (or use the Window Manager switch in Settings → Windows → Behavior); Mooring explains what macOS calls Accessibility and opens System Settings → Privacy & Security → Accessibility, and Windows switches on by itself once you grant it. If you later revoke it, Windows turns itself off and the icon shows an orange "!" that reads "Windows needs Accessibility". The Windows settings are in Settings → Windows, and General → Shortcuts lists every global shortcut and flags clashes with each other and with macOS.

### Agents can arrange windows

With Windows on, an agent can move and resize your windows from a plain request ("Chrome on the right half, iTerm bottom left"). `mooring win list` shows the windows, `mooring win arrange chrome=right-half iterm=bottom-left` places them in one go, and `mooring win undo` puts them back; the Claude Code plugin and the MCP tools (`list_windows`, `arrange_windows`, `undo_arrangement`, `save_layout`, `apply_layout`) do the same. `mooring win layout save coding` keeps an arrangement to apply later. Settings → Agents → "Window arrangement by agents" chooses Automatic, Ask first (a notification with Allow and Deny) or Off (agents can't even list windows). Agents get only regions that move and resize windows, so `mooring win undo` can always put them back.

## Clipboard

Mooring also includes a clipboard history, [Maccy](https://github.com/p0deje/Maccy), vendored as ClipKit. It is off by default: until you turn it on, Mooring records nothing, creates no history file and listens for no shortcut. Choose **Clipboard › Turn On…** in the menu (or the Clipboard switch in Settings → Clipboard → History), copy as usual, and press ⇧⌘C to search, pin and paste. Pasting automatically needs Accessibility, the same permission Windows uses; without it, choosing an item copies it and the popup reminds you to paste with ⌘V. Clipboard › in the menu lists your latest copies and has Pause Recording, Ignore Next Copy and Clear.

Mooring never records concealed or temporary copies (what password managers mark), copies made while Secure Keyboard Entry is on, copies from apps on the ignore list (1Password, Bitwarden, Dashlane, LastPass, KeePassXC, Keychain Access and Passwords by default) or copies from your other devices through Universal Clipboard unless you allow them. Settings → Clipboard → Ignore Rules edits the list.

### Agents can't read it

No `mooring` command, MCP tool, Shortcuts action, `mooring://` link or AppleScript call returns clipboard history, and tests fail the build if one appears. Mooring protects your clipboard *history*; any app can still read what you copied most recently, because that is how macOS pasteboards work. The history file (`~/Library/Application Support/Mooring/Clipboard/`) is kept in a folder only you can open and left out of backups, but it isn't encrypted, so any process running as you, including an agent with shell access, can read it. If that matters to you, leave Clipboard off. Turning Clipboard off stops recording but keeps what's saved; use Delete Clipboard History… in Settings → Clipboard to remove it.

## License

Copyright (C) 2026 Eidan Erlich. Licensed under GPL-3.0-only; the full text is in [LICENSE](LICENSE).

Mooring's window management is derived from [Loop](https://github.com/MrKai77/Loop), which is licensed under GPLv3, and that is why the whole app is GPLv3. The clipboard history comes from [Maccy](https://github.com/p0deje/Maccy) and the lid-closed mode from [Awayke](https://github.com/daemonphantom/Awayke), both under the MIT license; their code keeps its original copyright and permission notices. [THIRD_PARTY](THIRD_PARTY) has each upstream license and exactly what was taken. Every build also bundles `LICENSE` and `THIRD_PARTY_NOTICES.md` (those licenses plus every Swift package Mooring uses) in `Mooring.app/Contents/Resources/`; Settings → Mooring → Advanced → **Acknowledgements…** opens the notices.

## Credits

Mooring builds on four open-source projects:

- [Awayke](https://github.com/daemonphantom/Awayke) (MIT): lid-closed mode and the privileged helper
- [Chai](https://github.com/lvillani/chai) (GPL-3.0): one-click idle and display sleep prevention with durations, reimplemented rather than copied
- [Loop](https://github.com/MrKai77/Loop) (GPL-3.0): window management
- [Maccy](https://github.com/p0deje/Maccy) (MIT): clipboard history and the floating panel

It also uses Swift packages including Sparkle, Defaults, KeyboardShortcuts, Sauce, Luminare, Scribe and Subsurface; the bundled notices list them all.

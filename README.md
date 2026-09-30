# Mooring

Mooring is a free, open-source macOS menu-bar app that keeps your Mac awake, including with the lid closed, without a password prompt after a one-time approval. Scripts and coding agents drive the same engine through a `mooring` command.

> **Status:** early development. Nothing here keeps your Mac awake yet. The full design is in [docs/SPEC.md](docs/SPEC.md).

## Build from source

You need macOS 14 or later, Xcode, and [Homebrew](https://brew.sh).

```sh
make bootstrap   # installs XcodeGen and SwiftLint, generates Mooring.xcodeproj
make run         # Debug build, then launches the app; look for the anchor in the menu bar
make test        # unit tests for every package and the app
```

Builds are ad-hoc signed by default. To sign with your own Apple Development certificate, which lid mode will need, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and fill it in.

Other commands:

| Command | Does |
| --- | --- |
| `make build` | Debug build |
| `make lint` | SwiftLint |
| `make install` | Release build to `/Applications` |
| `make uninstall` | Quits Mooring and removes it from `/Applications` |
| `make reset-sleep` | Runs `sudo pmset -a disablesleep 0`, in case sleep is ever left disabled |
| `make clean` | Removes build output and the generated project |

## License

GPL-3.0-only; see [LICENSE](LICENSE). Code adapted from MIT-licensed projects keeps its original notices; see [THIRD_PARTY](THIRD_PARTY).

## Credits

Mooring builds on four open-source projects:

- [Awayke](https://github.com/daemonphantom/Awayke) (MIT): lid-closed mode and the privileged helper
- [Chai](https://github.com/lvillani/chai) (GPL-3.0): one-click idle and display sleep prevention with durations, reimplemented rather than copied
- [Loop](https://github.com/MrKai77/Loop) (GPL-3.0): window management
- [Maccy](https://github.com/p0deje/Maccy) (MIT): clipboard history and the floating panel

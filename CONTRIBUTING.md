# Contributing to Mooring

Thanks for helping. Bug reports, fixes and small improvements are welcome; for anything larger, open an issue first so we can agree on the approach. The design is in [docs/SPEC.md](docs/SPEC.md), with per-feature notes in [docs/design/](docs/design/), and known issues are in [docs/BACKLOG.md](docs/BACKLOG.md). Security problems go through [SECURITY.md](SECURITY.md), not an issue.

## Build and test

You need macOS 14 or later, Xcode 26 and [Homebrew](https://brew.sh).

```sh
make bootstrap   # once: installs XcodeGen and SwiftLint, generates Mooring.xcodeproj
make generate    # regenerate the project after changing project.yml or adding files
make test        # every package's tests, the script tests and the app's tests
make lint        # SwiftLint
make install     # Release build to /Applications
```

`Mooring.xcodeproj` is generated from `project.yml` and isn't committed; change `project.yml`, never the project. Package versions are pinned in `Config/Package.resolved`.

An unsigned test run, as CI does it, keeps clear of the signed build whose helper you may have registered:

```sh
make test DERIVED=build/Unsigned XCODEBUILD_FLAGS="CODE_SIGNING_ALLOWED=NO"
```

## Signing

Builds are ad-hoc signed unless you configure a certificate, and everything except lid mode works that way. Lid mode's helper only talks to an app signed with a stable certificate; a free Apple ID's personal team is enough. Copy [`Config/Local.xcconfig.example`](Config/Local.xcconfig.example) to `Config/Local.xcconfig` (gitignored) and set `MOORING_SIGN_IDENTITY` and `MOORING_TEAM`; the example says how to find both. Never commit `Config/Local.xcconfig`, certificates or provisioning profiles. After changing helper code, restart the helper with `sudo launchctl kickstart -k system/dev.mooring.helper`, and if sleep is ever left disabled, `make reset-sleep` turns it back on.

## Ground rules

- Only the helper runs `pmset`, every test that touches lid mode restores sleep, and the helper stays small with no dependencies.
- No network access in app code except the Sparkle updater.
- Clipboard history never reaches an agent: no command, MCP tool, link, intent or AppleScript route may touch ClipKit (`AgentWallTests` enforce it).
- Swift 6 strict concurrency, `@MainActor` for UI, `os.Logger` with subsystem `dev.mooring`. New behaviour comes with a test.
- Don't claim behaviour you couldn't observe (lid, battery, notifications, permission prompts) in a PR; say it needs a manual check.

## Vendored code

Awayke, Loop and Maccy are copied in as plain snapshots, without git history. The rules (SPEC.md, Development notes → Vendoring):

- Keep every copied file's original header. A file you change gets a first line `// Adapted from <repo>@<commit>: <original path>`.
- Record every change in `THIRD_PARTY/<Repo>/UPSTREAM.md` under Modifications, including edits to files that can't carry a header (such as string catalogs). `UPSTREAM.md` also lists every file taken.
- `THIRD_PARTY/<Repo>/` keeps the upstream `LICENSE`. A new vendored project or Swift package needs its license: the build writes `THIRD_PARTY_NOTICES.md` into the app from `THIRD_PARTY/` and the pinned packages, and fails if a package has no license file.
- Never copy Chai's icons, Loop's or Maccy's app icons, updaters or App Store review prompts.
- Changes offered back to Loop must follow Loop's `AI_POLICY.md`.

Vendored folders are excluded from SwiftLint (`.swiftlint.yml`); leave their style alone.

## Commits and pull requests

- One topic per pull request, with `make test` and `make lint` passing. CI runs an unsigned build, the tests and a release dry run.
- Commit subjects are short, imperative and capitalised, with no prefix or trailing period ("Keep a lease's reason when keep_awake extends it"). The body, when needed, says why.
- If an AI assistant wrote part of a change, say so with a `Co-Authored-By:` trailer.

By contributing, you agree that your contribution is licensed under GPL-3.0-only, like the rest of Mooring.

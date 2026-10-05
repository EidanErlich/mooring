# Stage 5: Release tooling

Oct 4, 2026 · Eidan Erlich · Status: built (shipped in 0.1.0)

## Goal

Everything needed to ship Mooring v0.1 is built and tested. **Nothing is published by the tooling.** Publishing is a handful of documented commands, run by hand.

The stage covers four things:
- **Updates:** a Sparkle updater, opt-in, with no network access unless the user turns it on and a public key is configured.
- **Uninstall:** in-app "Uninstall…", as SPEC Appendix A describes.
- **Release script:** `scripts/release.sh` builds the signed `Mooring-<version>.zip`, its EdDSA signature, the appcast entry and the Homebrew cask, into `dist/`.
- **README:** install docs.

## Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Publishing | **Not in this stage.** No GitHub Release, tag push, Pages deploy or tap repo is created. `scripts/release.sh --publish` prints the exact `gh` and `git` commands to run. The script never runs them itself. | Publishing is outward-facing, so a person does it. |
| Sparkle | Sparkle 2.x, at an exact version, linked into the app only. The feed URL is `https://eidanerlich.github.io/mooring/appcast.xml` (SPEC). The public EdDSA key comes from the build setting `MOORING_SPARKLE_PUBLIC_KEY` (`Config/Local.xcconfig`, empty by default) into `SUPublicEDKey`. **With no key configured, the updater is off and its UI hidden**, so local and CI builds never touch the network. | SPEC: Sparkle, with EdDSA keys kept in the maintainer's Keychain. A missing key must fail closed. |
| Update consent | The first launch with a configured key asks once, through an alert: "Check for updates automatically?" with **Check Automatically** and **Not Now**. Settings → Mooring → Advanced has "Check for updates automatically" and **Check Now**. Mooring makes no update check until the user agrees. | SPEC: "opt-in on first launch". |
| Generating keys | Never done by Mooring or its scripts. The README documents `generate_keys` from Sparkle's tools, run by the maintainer. | It writes to the maintainer's Keychain, which is a persistent security action. |
| Uninstall | Settings → Mooring → Advanced → **Uninstall Mooring…** shows a confirmation sheet listing what will happen, with an "Also delete clipboard history" checkbox (off), and **Uninstall** / **Cancel**. Steps:<br>1. End all leases, so sleep returns to normal.<br>2. Ask the helper to set `disablesleep 0`.<br>3. Unregister the helper (`SMAppService`) and the login item.<br>4. Remove `~/.local/bin/mooring` if it links to this app.<br>5. Remove the Claude plugin entries and the MCP client entries Mooring added, using the existing removers.<br>6. If checked, delete `…/Mooring/Clipboard/`.<br>7. Delete Mooring's settings domains (`dev.mooring.windows`, `dev.mooring.clipboard`).<br>8. Move the app to the Trash (`NSWorkspace.recycle`).<br>9. Quit. | SPEC Appendix A. Each step reuses existing code. |
| `make uninstall` | Also removes `~/.local/bin/mooring` when it points into `/Applications/Mooring.app`. | Backlog item, and SPEC's Repository setup says so. |
| Release script | `scripts/release.sh [--dry-run] [--publish]` does the following:<br>1. Checks the tree is clean and the version tag is absent.<br>2. Runs `make test`.<br>3. Builds Release with the `Local.xcconfig` identity.<br>4. Verifies with `codesign --verify --deep --strict`.<br>5. Zips with `ditto -c -k --sequesterRsrc --keepParent` (extended attributes in `__MACOSX/`, so a plain `unzip` keeps the code seal) → `dist/Mooring-<v>.zip`.<br>6. Signs with Sparkle's `sign_update` (the maintainer's Keychain key) → `dist/Mooring-<v>.zip.sig`.<br>7. Writes `dist/appcast.xml` (one item; version, length, `sparkle:edSignature`, minimum system 14.0).<br>8. Writes `dist/homebrew/mooring.rb`, a cask for the tap `EidanErlich/homebrew-tap`, with the sha256, `auto_updates true`, `uninstall quit: "dev.mooring.app"`, a `zap trash:` for `~/Library/Application Support/Mooring` and the three preference plists, and `caveats` advice on quarantine.<br>A real run refuses a build with an empty `SUPublicEDKey` or one that isn't signed with a certificate (see "As built").<br>`--dry-run` skips signing and testing, and uses an existing built app (for CI and tests). `--publish` only prints the commands. | SPEC stage 5. |
| Version | `MARKETING_VERSION` becomes **0.1.0**, and the plugin stays 0.0.4. The tag `v0.1.0` is **not** created. | Tagging is part of publishing, which is done by hand. |
| CI | A `release-dry-run` step after the tests runs `scripts/release.sh --dry-run --app build/…/Mooring.app` and checks that `dist/` holds the zip, appcast and cask, and that they parse (`xmllint --noout`, `ruby -c`). | It proves the tooling without secrets. |
| README | An Install section covering:<br>• build from source (`make install`);<br>• the prebuilt zip and the quarantine fix, quoting SPEC Appendix A;<br>• Homebrew (`brew install --cask eidanerlich/tap/mooring`, "once the tap is published");<br>• updates;<br>• uninstall.<br>Also a "Releasing" note for maintainers: key generation, `Local.xcconfig`, and `scripts/release.sh`. | SPEC stage 5. |

## Testing

- **Updater:**
  - a missing key leaves the updater disabled, with nothing scheduled;
  - with a key, the consent alert shows once;
  - "Not Now" leaves automatic checks off;
  - "Check Automatically" turns them on;
  - "Check Now" calls the updater.

  All through an injected `UpdaterDriving` protocol, never real Sparkle network calls.
- **Uninstall:** each step is called in order through injected seams; the clipboard folder is deleted only when ticked; a failed step continues and is reported at the end; Cancel does nothing.
- **Release script:** run under `scripts/test-release.sh` against a fixture `.app` (a tiny signed stub, or the unsigned test build). It asserts:
  - the zip unzips to `Mooring.app`;
  - the appcast is well-formed XML with the version and length;
  - the cask has the right sha256;
  - `--publish` prints and runs nothing.

  It's wired into `make test`.
- **`make uninstall`:** a script test using a temporary `HOME`.

## Manual check

1. Generate the Sparkle keys, and put the public key in `Local.xcconfig`.
2. Run `bash scripts/release.sh --publish` once and inspect the `dist/` it built (no second build).
3. Install from the zip on a second user account, and confirm the quarantine fix works.
4. When publishing: create the tap repo, enable Pages, and run the commands step 2 printed; the first block tags v0.1.0, so afterwards only verify it (`git tag -l`, `git ls-remote --tags origin`).

## As built: final review fixes

The final whole-branch review found three things to fix before v0.1.0 and a few cheap minors. As built:

- **Gentle update reminders.** A menu-bar app has no Dock icon and can't be Cmd-Tabbed to, so Sparkle's scheduled update alert, shown behind other apps when Mooring isn't active, is easy to miss, and the 0.1.0 binary presents every later update. `LiveSparkleUpdater` now has an `SPUStandardUserDriverDelegate` (`supportsGentleScheduledUpdateReminders = true`). Sparkle shows a scheduled update only when it would be in immediate focus. Otherwise `UpdateReminder` posts a notification ("Mooring <version> is available", "Open the menu bar icon to update.") and the dropdown gets **Update Available…** after Settings…, which calls Check Now. The user's attention, or the end of the update session, clears both.
- **Release checks.** After the build, a real run refuses an app whose `SUPublicEDKey` is empty ("Set MOORING_SPARKLE_PUBLIC_KEY in Config/Local.xcconfig — see docs/RELEASING.md") or whose `codesign -dv` shows `Signature=adhoc`, or no Authority or TeamIdentifier ("Set MOORING_SIGN_IDENTITY …"). Either mistake would otherwise ship a release that can never update itself, or one that loses its TCC and helper trust.
- **Zip.** `ditto -c -k --sequesterRsrc --keepParent`. Without `--sequesterRsrc`, every extended attribute becomes a `._` file that a plain `unzip` drops inside `Mooring.app`, which breaks the code seal.
- **Uninstall cleanup.** A step after the clipboard one deletes `leases.json`, `layouts.json` and `mooring.sock` from `~/Library/Application Support/Mooring/`, by exact name. The folder goes only if it's then empty. The settings domains are removed again in `applicationWillTerminate`. If restoring sleep failed, the summary says "Sleep may still be disabled. Run in Terminal: sudo pmset -a disablesleep 0". The Advanced caption lists what is removed.
- **Cask and CI.** The cask declares `auto_updates true`, `uninstall quit:` and `zap trash:`. The CI dry run also runs `ruby -c` on the cask.

## Out of scope

- Developer ID signing and notarization (SPEC: no paid account).
- Delta updates.
- Automatic publishing.

# Stage 5: Release tooling

Oct 4, 2026 · Eidan Erlich · Status: design decided under the owner's standing instruction to complete the project end to end. It follows SPEC.md Appendix A and the owner's standing "keep it private for now".

## Goal

Everything needed to ship Mooring v0.1 is built and tested. **Nothing is published.** The owner runs one documented command to publish when they choose to go public.

The stage covers four things:
- **Updates:** a Sparkle updater, opt-in, with no network access unless the user turns it on and a public key is configured.
- **Uninstall:** in-app "Uninstall…", as SPEC Appendix A describes.
- **Release script:** `scripts/release.sh` builds the signed `Mooring-<version>.zip`, its EdDSA signature, the appcast entry and the Homebrew cask, into `dist/`.
- **README:** install docs.

## Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Publishing | **Not in this stage.** No GitHub Release, tag push, Pages deploy or tap repo is created. `scripts/release.sh --publish` prints the exact `gh` and `git` commands the owner runs. The script never runs them itself. | The owner said "keep it private for now". Publishing is outward-facing. |
| Sparkle | Sparkle 2.x, at an exact version, linked into the app only. The feed URL is `https://eidanerlich.github.io/mooring/appcast.xml` (SPEC). The public EdDSA key comes from the build setting `MOORING_SPARKLE_PUBLIC_KEY` (`Config/Local.xcconfig`, empty by default) into `SUPublicEDKey`. **With no key configured, the updater is off and its UI hidden**, so local and CI builds never touch the network. | SPEC: Sparkle, with EdDSA keys kept in the owner's Keychain. A missing key must fail closed. |
| Update consent | The first launch with a configured key asks once, through an alert: "Check for updates automatically?" with **Check Automatically** and **Not Now**. Settings → Mooring → Advanced has "Check for updates automatically" and **Check Now**. Mooring makes no update check until the user agrees. | SPEC: "opt-in on first launch". |
| Generating keys | Never done by Mooring or its scripts. The README documents `generate_keys` from Sparkle's tools, run by the owner. | It writes to the owner's Keychain, which is a persistent security action. |
| Uninstall | Settings → Mooring → Advanced → **Uninstall Mooring…** shows a confirmation sheet listing what will happen, with an "Also delete clipboard history" checkbox (off), and **Uninstall** / **Cancel**. Steps:<br>1. End all leases, so sleep returns to normal.<br>2. Ask the helper to set `disablesleep 0`.<br>3. Unregister the helper (`SMAppService`) and the login item.<br>4. Remove `~/.local/bin/mooring` if it links to this app.<br>5. Remove the Claude plugin entries and the MCP client entries Mooring added, using the existing removers.<br>6. If checked, delete `…/Mooring/Clipboard/`.<br>7. Delete Mooring's settings domains (`dev.mooring.windows`, `dev.mooring.clipboard`).<br>8. Move the app to the Trash (`NSWorkspace.recycle`).<br>9. Quit. | SPEC Appendix A. Each step reuses existing code. |
| `make uninstall` | Also removes `~/.local/bin/mooring` when it points into `/Applications/Mooring.app`. | Backlog item, and SPEC's Repository setup says so. |
| Release script | `scripts/release.sh [--dry-run] [--publish]` does the following:<br>1. Checks the tree is clean and the version tag is absent.<br>2. Runs `make test`.<br>3. Builds Release with the `Local.xcconfig` identity.<br>4. Verifies with `codesign --verify --deep --strict`.<br>5. Zips with `ditto -c -k --sequesterRsrc --keepParent` (extended attributes in `__MACOSX/`, so a plain `unzip` keeps the code seal) → `dist/Mooring-<v>.zip`.<br>6. Signs with Sparkle's `sign_update` (the owner's Keychain key) → `dist/Mooring-<v>.zip.sig`.<br>7. Writes `dist/appcast.xml` (one item; version, length, `sparkle:edSignature`, minimum system 14.0).<br>8. Writes `dist/homebrew/mooring.rb`, a cask for the tap `EidanErlich/homebrew-tap`, with the sha256, plus `postflight` advice on quarantine.<br>`--dry-run` skips signing and testing, and uses an existing built app (for CI and tests). `--publish` only prints the commands. | SPEC stage 5. |
| Version | `MARKETING_VERSION` becomes **0.1.0**, and the plugin stays 0.0.4. The tag `v0.1.0` is **not** created. | SPEC: "Tags v0.1" is the owner's checkpoint. |
| CI | A `release-dry-run` step after the tests runs `scripts/release.sh --dry-run --app build/…/Mooring.app` and checks that `dist/` holds the zip, appcast and cask, and that they parse. | It proves the tooling without secrets. |
| README | An Install section covering:<br>• build from source (`make install`);<br>• the prebuilt zip and the quarantine fix, quoting SPEC Appendix A;<br>• Homebrew (`brew install --cask eidanerlich/tap/mooring`, "once the tap is published");<br>• updates;<br>• uninstall.<br>Also a "Releasing" note for the owner: key generation, `Local.xcconfig`, and `scripts/release.sh`. | SPEC stage 5. |

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

## Owner check

1. Generate the Sparkle keys, and put the public key in `Local.xcconfig`.
2. Run `scripts/release.sh` and inspect `dist/`.
3. Install from the zip on a second user account, and confirm the quarantine fix works.
4. When ready to go public: create the tap repo, enable Pages, and run the printed `--publish` commands, then tag v0.1.0.

## Out of scope

- Developer ID signing and notarization (SPEC: no paid account).
- Delta updates.
- Automatic publishing.

# Releasing Mooring

The maintainer's checklist for publishing a release. Everything here runs on your Mac, with your Keychain. Nothing in the repo, its scripts or CI publishes anything: `scripts/release.sh --publish` (step 4) builds once and only **prints** the publishing commands, and you run them yourself in step 7.

Mooring has no paid Apple account, so a release is signed with the maintainer's own certificate (yours, not notarized) and updates are verified with Sparkle's EdDSA signature instead. Keep using the same signing certificate for every release, so people's Accessibility grants survive updates; if it ever changes, say so in the release notes.

## Signing identity and privacy

Your release certificate's name and your Team ID are embedded in every app you sign, and anyone who downloads a release can read them with `codesign -dv /Applications/Mooring.app` (the `Authority=` and `TeamIdentifier=` lines). For an Apple Development certificate, the name is `Apple Development: <your Apple ID email> (<certificate id>)`, so a release signed with your personal Apple ID publishes that email address.

To keep a personal email out of releases, create a separate free Apple ID just for the project, add it in Xcode → Settings → Accounts, and sign releases with the Apple Development certificate of its personal team (its identity and Team ID go in `Config/Local.xcconfig`). Decide before the first release: changing the certificate later means everyone has to grant Accessibility again. Never commit `Config/Local.xcconfig`, certificates (`.p12`, `.cer`) or provisioning profiles; `.gitignore` already excludes them.

## Before you start

- The repository `EidanErlich/mooring` must be public when you publish. Sparkle fetches the appcast from GitHub Pages and the zip from a GitHub Release, and Homebrew downloads the same zip. A private repo serves neither.
- `Config/Local.xcconfig` (gitignored) must name your signing certificate; copy `Config/Local.xcconfig.example` and fill it in.
- You are on `main` with a clean tree. `scripts/release.sh` refuses a dirty tree and a version whose `v<version>` tag already exists, here or on `origin` (`git ls-remote --tags origin`). If it can't reach `origin`, it warns "Couldn't check origin for tag v<version>" and goes on, so look at the repo's tags yourself before publishing.

## 1. Install Sparkle's tools and generate the signing key

Build once so Swift Package Manager fetches Sparkle, then use the tools it unpacked:

```sh
make build
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

`generate_keys` creates an EdDSA key pair. The **private key stays in your login Keychain**, and the command prints the **public key**. Don't paste the private key anywhere, and never commit it. Mooring and its scripts never generate or read it; only Sparkle's `sign_update` does, when you run the release.

If you use a different derived-data folder, look for `…/SourcePackages/artifacts/sparkle/Sparkle/bin/` under it, or set `SIGN_UPDATE=/path/to/sign_update` when you run the release.

Losing this key means installed copies can't verify future updates, so back it up once:

```sh
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/mooring-sparkle-key
```

Write the backup **outside the repo** (never into the working tree, where it could be committed) and outside synced folders such as Desktop or Documents in iCloud. Move it to offline storage (an encrypted USB drive or a password manager's secure file), then delete the local copy (`rm ~/mooring-sparkle-key`). `generate_keys -f <file>` imports it again.

## 2. Put the public key in `Config/Local.xcconfig`

```
MOORING_SPARKLE_PUBLIC_KEY = <the public key generate_keys printed>
```

This becomes `SUPublicEDKey` in the app's `Info.plist`. With it empty (the default), the app has no updater and makes no network requests. With it set, Mooring asks once on first launch whether to check automatically, and Settings → Mooring → Advanced gets **Check for updates automatically** and **Check Now**. The feed is `https://eidanerlich.github.io/mooring/appcast.xml`.

## 3. Bump the version

Set `MARKETING_VERSION` in `Config/Shared.xcconfig` (it is `0.1.0` for the first release). `CURRENT_PROJECT_VERSION = $(MARKETING_VERSION)`, so the build number follows it and the appcast's `sparkle:version` always rises. The Claude Code plugin has its own version (`plugin.json`), which changes only when its files do and never exceeds `MARKETING_VERSION`.

Commit the bump, merge it to `main` and push `main`, so the tag in step 7 points at a commit GitHub has.

## 4. Build, sign and print the publishing commands

```sh
bash scripts/release.sh --publish
```

This is the one build of the release. The script:

1. checks the tree is clean and the tag is unused, locally and on `origin`;
2. runs `make test`;
3. builds Release with the identity in `Local.xcconfig` (`make build-release`);
4. refuses the build if `Contents/Resources/` lacks `LICENSE` or `THIRD_PARTY_NOTICES.md`, if its `SUPublicEDKey` is empty (a release without it could never update itself), or if it isn't signed with a certificate (ad-hoc, or no Authority or TeamIdentifier in `codesign -dv`);
5. verifies it with `codesign --verify --deep --strict`;
6. zips it with `ditto -c -k --sequesterRsrc --keepParent` (extended attributes go in `__MACOSX/`, so even a plain `unzip` gives an intact app);
7. signs the zip with Sparkle's `sign_update`, using the key in your Keychain (macOS may ask to allow access);
8. writes the appcast and the Homebrew cask;
9. prints three blocks of publishing commands for step 7, and runs none of them.

(`make release` is the same run without `--publish`: it builds `dist/` but prints no commands. It passes flags in `ARGS`, so `make release ARGS=--publish` is step 4.)

## 5. Inspect `dist/`

Inspect the `dist/` that step 4 just built; the commands it printed publish exactly these files. `dist/` is gitignored and holds:

| File | What it is |
| --- | --- |
| `Mooring-<version>.zip` | The app, zipped with `Mooring.app` at the top |
| `Mooring-<version>.zip.sig` | `sign_update`'s output for the zip |
| `appcast.xml` | One `<item>`: version, `sparkle:version`, minimum macOS, a `sparkle:releaseNotesLink` to the GitHub Release, the zip's byte length and `sparkle:edSignature` |
| `homebrew/mooring.rb` | The cask for the tap, with the zip's sha256, `auto_updates true`, `uninstall quit:` and `zap trash:` |

Check that:

- `unzip -l dist/Mooring-<version>.zip` shows `Mooring.app/…`, including `Mooring.app/Contents/Resources/LICENSE` and `Mooring.app/Contents/Resources/THIRD_PARTY_NOTICES.md`, and the unzipped app passes `codesign --verify --deep --strict`;
- `THIRD_PARTY_NOTICES.md` lists every vendored project and Swift package. Every build writes it from `THIRD_PARTY/*/` and the licenses of the packages pinned in `Config/Package.resolved` (`scripts/third-party-notices.sh`, run by the "Bundle license notices" build phase), and the build fails if a pinned package has no license file, so there is nothing to regenerate by hand. When you add a vendored project, give it a `THIRD_PARTY/<Repo>/` folder first;
- `appcast.xml` has a non-empty `sparkle:edSignature`, `length` equals `stat -f%z dist/Mooring-<version>.zip`, and `xmllint --noout dist/appcast.xml` is quiet;
- the cask's `sha256` equals `shasum -a 256 dist/Mooring-<version>.zip`, and its caveats offer **Open Anyway** or `xattr -dr com.apple.quarantine /Applications/Mooring.app`;
- the built app has your public key (the script already refuses an empty one): `plutil -extract SUPublicEDKey raw build/DerivedData/Build/Products/Release/Mooring.app/Contents/Info.plist`.

If anything is wrong, fix it and run step 4 again; nothing has been published yet.

(`scripts/release.sh --dry-run --app <path to a built Mooring.app>` makes the same files without tests, a build or signing; its appcast signature is empty. CI runs it on every push, and `--dry-run` can't be combined with `--publish`.)

## 6. Create the tap and enable Pages

Both are one-time setup. Do them in your browser or with `gh`, but only when you are ready to go public.

1. **Tap:** create the public repo `EidanErlich/homebrew-tap` (empty is fine; the script adds `Casks/mooring.rb`). Users then install with `brew install --cask eidanerlich/tap/mooring`.
2. **Pages for the appcast:** the printed commands push `appcast.xml` to a `gh-pages` branch of `EidanErlich/mooring`, so that branch has to exist first. Create it with a single commit (for example an empty one in a throwaway clone: `git switch --orphan gh-pages && git commit --allow-empty -m "Start Pages" && git push origin gh-pages`). Then in the repo's Settings → Pages, choose "Deploy from a branch", branch `gh-pages`, folder `/ (root)`. The feed is then served at `https://eidanerlich.github.io/mooring/appcast.xml`.

## 7. Run the printed publishing commands

Don't run the script again: a rerun rebuilds and re-signs `dist/`, and its zip would no longer be the one you inspected. Scroll back to the three blocks step 4 printed (if they've scrolled away, `bash -c '. scripts/release.sh && print_publish <version>'` prints them again without building anything):

1. `git tag v<version> && git push origin v<version>`, then `gh release create v<version> dist/Mooring-<version>.zip --generate-notes`;
2. a clone of `gh-pages`, a copy of `dist/appcast.xml` into it, then commit and push;
3. a clone of the tap, a copy of `dist/homebrew/mooring.rb` to `Casks/mooring.rb`, then commit and push.

Blocks 2 and 3 clone over `https`, which needs Git credentials for GitHub. If you haven't already, run `gh auth setup-git` once so Git uses your `gh` login.

Read them, then run them from the repo root, in order. Block 1 is the only place the release is tagged.

## 8. Verify the tag

Block 1 tagged `v<version>` and pushed the tag. Don't tag by hand; just confirm both sides have it:

```sh
git tag -l
git ls-remote --tags origin
```

## 9. Check a clean install on a second user account

Create (or use) another macOS user, so nothing is left over from your own builds, and log in as them:

1. Download `Mooring-<version>.zip` from the GitHub Release in Safari, unzip it and move `Mooring.app` to `/Applications`.
2. Open it. macOS should block it as from an unidentified developer.
3. Confirm the quarantine fix works both ways, on a fresh copy each time: **System Settings → Privacy & Security → Open Anyway**, and `xattr -dr com.apple.quarantine /Applications/Mooring.app`.
4. Check the first launch asks "Check for updates automatically?" once, and that Settings → Mooring → Advanced has **Check for updates automatically** and **Check Now**.
5. After `brew install --cask eidanerlich/tap/mooring`, check Mooring installs and opens the same way and the caveats print the quarantine advice.
6. Try **Uninstall Mooring…** in Settings → Mooring → Advanced, and confirm the app is in the Trash and `~/Library/Application Support/Mooring` has no `leases.json`, `layouts.json` or `mooring.sock`.

Updating can't be tested with the first release, since nothing older has the updater. When you publish the next version, install the previous one first and use **Check Now**.

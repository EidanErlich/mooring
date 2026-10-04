# Releasing Mooring

The owner's checklist for publishing a release. Everything here runs on your Mac, with your Keychain. Nothing in the repo, its scripts or CI publishes anything: `scripts/release.sh --publish` only **prints** the commands in step 7, and you run them yourself.

Mooring has no paid Apple account, so a release is signed with your own certificate (not notarized) and updates are verified with Sparkle's EdDSA signature instead. Keep using the same signing certificate for every release, so people's Accessibility grants survive updates; if it ever changes, say so in the release notes.

## Before you start

- The repository `EidanErlich/mooring` must be public when you publish. Sparkle fetches the appcast from GitHub Pages and the zip from a GitHub Release, and Homebrew downloads the same zip. A private repo serves neither.
- `Config/Local.xcconfig` (gitignored) must name your signing certificate; copy `Config/Local.xcconfig.example` and fill it in.
- You are on `main` with a clean tree. `scripts/release.sh` refuses a dirty tree and a version whose `v<version>` tag already exists here. That tag check is local only: it can't see a tag that exists only on GitHub, so look at the repo's tags yourself.

## 1. Install Sparkle's tools and generate the signing key

Build once so Swift Package Manager fetches Sparkle, then use the tools it unpacked:

```sh
make build
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

`generate_keys` creates an EdDSA key pair. The **private key stays in your login Keychain**, and the command prints the **public key**. Don't paste the private key anywhere, and never commit it. Mooring and its scripts never generate or read it; only Sparkle's `sign_update` does, when you run the release.

If you use a different derived-data folder, look for `…/SourcePackages/artifacts/sparkle/Sparkle/bin/` under it, or set `SIGN_UPDATE=/path/to/sign_update` when you run the release.

Losing this key means installed copies can't verify future updates. Consider exporting a backup (`generate_keys -x <file>`) to somewhere safe and offline.

## 2. Put the public key in `Config/Local.xcconfig`

```
MOORING_SPARKLE_PUBLIC_KEY = <the public key generate_keys printed>
```

This becomes `SUPublicEDKey` in the app's `Info.plist`. With it empty (the default), the app has no updater and makes no network requests. With it set, Mooring asks once on first launch whether to check automatically, and Settings → Mooring → Advanced gets **Check for updates automatically** and **Check Now**. The feed is `https://eidanerlich.github.io/mooring/appcast.xml`.

## 3. Bump the version

Set `MARKETING_VERSION` in `Config/Shared.xcconfig` (it is `0.1.0` for the first release). `CURRENT_PROJECT_VERSION = $(MARKETING_VERSION)`, so the build number follows it and the appcast's `sparkle:version` always rises. The Claude Code plugin has its own version (`plugin.json`), which changes only when its files do and never exceeds `MARKETING_VERSION`.

Commit the bump, merge it to `main` and push `main`, so the tag in step 7 points at a commit GitHub has.

## 4. Build the release

```sh
make release
```

This runs `scripts/release.sh`, which:

1. checks the tree is clean and the tag is unused;
2. runs `make test`;
3. builds Release with the identity in `Local.xcconfig` (`make build-release`);
4. verifies it with `codesign --verify --deep --strict`;
5. zips it with `ditto -c -k --keepParent`;
6. signs the zip with Sparkle's `sign_update`, using the key in your Keychain (macOS may ask to allow access);
7. writes the appcast and the Homebrew cask.

`make release` passes no flags. To use one, call the script directly: `bash scripts/release.sh --publish` (step 7).

## 5. Inspect `dist/`

`dist/` is gitignored and holds:

| File | What it is |
| --- | --- |
| `Mooring-<version>.zip` | The app, zipped with `Mooring.app` at the top |
| `Mooring-<version>.zip.sig` | `sign_update`'s output for the zip |
| `appcast.xml` | One `<item>`: version, `sparkle:version`, minimum macOS, the zip's byte length and `sparkle:edSignature` |
| `homebrew/mooring.rb` | The cask for the tap, with the zip's sha256 |

Check that:

- `unzip -l dist/Mooring-<version>.zip` shows `Mooring.app/…`, and the unzipped app passes `codesign --verify --deep --strict`;
- `appcast.xml` has a non-empty `sparkle:edSignature`, `length` equals `stat -f%z dist/Mooring-<version>.zip`, and `xmllint --noout dist/appcast.xml` is quiet;
- the cask's `sha256` equals `shasum -a 256 dist/Mooring-<version>.zip`, and its caveats offer **Open Anyway** or `xattr -dr com.apple.quarantine /Applications/Mooring.app`;
- the built app has your public key: `plutil -extract SUPublicEDKey raw build/DerivedData/Build/Products/Release/Mooring.app/Contents/Info.plist`.

(`scripts/release.sh --dry-run --app <path to a built Mooring.app>` makes the same files without tests, a build or signing; its appcast signature is empty. CI runs it on every push, and `--dry-run` can't be combined with `--publish`.)

## 6. Create the tap and enable Pages

Both are one-time setup. Do them in your browser or with `gh`, but only when you are ready to go public.

1. **Tap:** create the public repo `EidanErlich/homebrew-tap` (empty is fine; the script adds `Casks/mooring.rb`). Users then install with `brew install --cask eidanerlich/tap/mooring`.
2. **Pages for the appcast:** the printed commands push `appcast.xml` to a `gh-pages` branch of `EidanErlich/mooring`, so that branch has to exist first. Create it with a single commit (for example an empty one in a throwaway clone: `git switch --orphan gh-pages && git commit --allow-empty -m "Start Pages" && git push origin gh-pages`). Then in the repo's Settings → Pages, choose "Deploy from a branch", branch `gh-pages`, folder `/ (root)`. The feed is then served at `https://eidanerlich.github.io/mooring/appcast.xml`.

## 7. Run the printed publishing commands

```sh
bash scripts/release.sh --publish
```

This is a full real run (steps 4 and 5 again, so `dist/` is rebuilt and the zip, appcast and cask stay consistent with each other), and it then prints three blocks of commands without running any:

1. `git tag v<version> && git push origin v<version>`, then `gh release create v<version> dist/Mooring-<version>.zip --generate-notes`;
2. a clone of `gh-pages`, a copy of `dist/appcast.xml` into it, then commit and push;
3. a clone of the tap, a copy of `dist/homebrew/mooring.rb` to `Casks/mooring.rb`, then commit and push.

Read them, then run them from the repo root, in order.

## 8. Tag

The first printed command tags `v<version>` and pushes the tag. If you ran it, confirm with `git tag -l` and `git ls-remote --tags origin`; if you split the steps, tag the same commit you released:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

Do this once per release, and only after the zip, appcast and cask are published.

## 9. Check a clean install on a second user account

Create (or use) another macOS user, so nothing is left over from your own builds, and log in as them:

1. Download `Mooring-<version>.zip` from the GitHub Release in Safari, unzip it and move `Mooring.app` to `/Applications`.
2. Open it. macOS should block it as from an unidentified developer.
3. Confirm the quarantine fix works both ways, on a fresh copy each time: **System Settings → Privacy & Security → Open Anyway**, and `xattr -dr com.apple.quarantine /Applications/Mooring.app`.
4. Check the first launch asks "Check for updates automatically?" once, and that Settings → Mooring → Advanced has **Check for updates automatically** and **Check Now**.
5. After `brew install --cask eidanerlich/tap/mooring`, check Mooring installs and opens the same way and the caveats print the quarantine advice.
6. Try **Uninstall Mooring…** in Settings → Mooring → Advanced, and confirm the app is in the Trash.

Updating can't be tested with the first release, since nothing older has the updater. When you publish the next version, install the previous one first and use **Check Now**.

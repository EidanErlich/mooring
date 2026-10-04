#!/bin/bash
# Tests scripts/release.sh in a sandbox: temporary git repos, a fixture Mooring.app and PATH shims for
# `gh` and `git push` that fail loudly. It never builds, signs, publishes, pushes or tags anything real.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RELEASE="$ROOT/scripts/release.sh"
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
# A space in every path checks the script's quoting.
WORK="$BASE/release test"
mkdir -p "$WORK"

REAL_GIT="$(command -v git)"
failures=0

check() { # name, condition result (0 = pass)
    if [ "$2" -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}

# A fixture app outside any repo: $1 is the directory, $2 the version.
fixture_app() {
    local app="$1/Mooring.app"
    mkdir -p "$app/Contents/MacOS"
    printf 'binary' > "$app/Contents/MacOS/Mooring"
    local plist="$app/Contents/Info.plist"
    plutil -create xml1 "$plist"
    plutil -insert CFBundleShortVersionString -string "$2" "$plist"
    plutil -insert CFBundleVersion -string 7 "$plist"
    plutil -insert LSMinimumSystemVersion -string 14.0 "$plist"
    plutil -insert CFBundleExecutable -string Mooring "$plist"
    echo "$app"
}

# A fresh git repo with the files release.sh reads; prints its path.
fresh_repo() {
    local repo="$WORK/$1/repo"
    mkdir -p "$repo/Config"
    printf 'MARKETING_VERSION = %s\n' "${2:-9.9.9}" > "$repo/Config/Shared.xcconfig"
    printf 'dist/\nbuild/\n' > "$repo/.gitignore"
    "$REAL_GIT" -C "$repo" init -q
    "$REAL_GIT" -C "$repo" add -A
    "$REAL_GIT" -C "$repo" -c user.name=Test -c user.email=test@example.invalid commit -q -m init
    echo "$repo"
}

# Shims that fail loudly (and leave a trace) when release.sh would publish. Others pass through to git.
shims() {
    local bin="$WORK/$1/bin"
    mkdir -p "$bin"
    printf '#!/bin/sh\necho "gh $*" >> "%s/forbidden.log"\necho "gh was called" >&2\nexit 97\n' "$WORK/$1" > "$bin/gh"
    cat > "$bin/git" <<SHIM
#!/bin/sh
for arg in "\$@"; do
    if [ "\$arg" = push ]; then
        echo "git \$*" >> "$WORK/$1/forbidden.log"
        echo "git push was called" >&2
        exit 97
    fi
done
exec "$REAL_GIT" "\$@"
SHIM
    chmod +x "$bin/gh" "$bin/git"
    echo "$bin"
}

# Runs release.sh in $1 (a repo) with the shims first in PATH. Output in $1/../out; sets CODE.
run_release() {
    local repo="$1"; shift
    local case_dir
    case_dir="$(dirname "$repo")"
    (cd "$repo" && PATH="$case_dir/bin:$PATH" bash "$RELEASE" "$@") >"$case_dir/out" 2>&1
    CODE=$?
}

# --- happy path: dry run against the fixture app -------------------------------------------------
repo="$(fresh_repo happy)"; case_dir="$(dirname "$repo")"; shims happy >/dev/null
app="$(fixture_app "$WORK/happy/built app" 9.9.9)"
# Built files carry extended attributes (com.apple.provenance); the zip must not turn them into ._ files.
xattr -w com.example.test 1 "$app/Contents/MacOS/Mooring"
run_release "$repo" --dry-run --check-git --app "$app"
dist="$repo/dist"
zip="$dist/Mooring-9.9.9.zip"
check "dry run: exits 0" "$([ "$CODE" -eq 0 ]; echo $?)"
check "dry run: zip, appcast and cask written" "$([ -s "$zip" ] && [ -s "$dist/appcast.xml" ] && [ -s "$dist/homebrew/mooring.rb" ]; echo $?)"

unzipped="$WORK/happy/unzipped"
mkdir -p "$unzipped"
ditto -x -k "$zip" "$unzipped" 2>/dev/null
check "zip round-trips to Mooring.app" "$([ -f "$unzipped/Mooring.app/Contents/Info.plist" ] && cmp -s "$unzipped/Mooring.app/Contents/Info.plist" "$app/Contents/Info.plist" && cmp -s "$unzipped/Mooring.app/Contents/MacOS/Mooring" "$app/Contents/MacOS/Mooring"; echo $?)"
check "ditto keeps the extended attribute" "$([ "$(xattr -p com.example.test "$unzipped/Mooring.app/Contents/MacOS/Mooring" 2>/dev/null)" = 1 ]; echo $?)"
check "zip has no ._ entries inside Mooring.app" "$(unzip -Z1 "$zip" | grep -v '^__MACOSX/' | grep -q '\(^\|/\)\._'; [ $? -ne 0 ]; echo $?)"
check "zip still lists Mooring.app" "$(unzip -Z1 "$zip" | grep -q '^Mooring.app/Contents/MacOS/Mooring$'; echo $?)"
plain="$WORK/happy/plain unzip"
mkdir -p "$plain"
unzip -q "$zip" -d "$plain" 2>/dev/null
check "plain unzip leaves no ._ files in Mooring.app" "$([ -f "$plain/Mooring.app/Contents/Info.plist" ] && [ -z "$(find "$plain/Mooring.app" -name '._*')" ]; echo $?)"

size="$(stat -f%z "$zip")"
check "appcast is well-formed XML" "$(xmllint --noout "$dist/appcast.xml" 2>/dev/null; echo $?)"
check "appcast has the version" "$(grep -q '<sparkle:shortVersionString>9.9.9</sparkle:shortVersionString>' "$dist/appcast.xml"; echo $?)"
check "appcast has the build number" "$(grep -q '<sparkle:version>7</sparkle:version>' "$dist/appcast.xml"; echo $?)"
check "appcast has the zip length" "$(grep -q "length=\"$size\"" "$dist/appcast.xml"; echo $?)"
check "appcast has the release URL" "$(grep -q 'url="https://github.com/EidanErlich/mooring/releases/download/v9.9.9/Mooring-9.9.9.zip"' "$dist/appcast.xml"; echo $?)"
check "appcast has the minimum system version" "$(grep -q '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>' "$dist/appcast.xml"; echo $?)"
check "dry-run appcast has an empty signature" "$(grep -q 'sparkle:edSignature=""' "$dist/appcast.xml"; echo $?)"

sha="$(shasum -a 256 "$zip" | awk '{print $1}')"
cask="$dist/homebrew/mooring.rb"
check "cask sha256 matches the zip" "$(grep -q "^  sha256 \"$sha\"$" "$cask"; echo $?)"
check "cask has the version and URL" "$(grep -q '^  version "9.9.9"$' "$cask" && grep -q 'releases/download/v#{version}/Mooring-#{version}.zip' "$cask"; echo $?)"
check "cask has the app and macOS floor" "$(grep -q '^  app "Mooring.app"$' "$cask" && grep -q 'depends_on macos: ">= :sonoma"' "$cask"; echo $?)"
check "cask mentions Open Anyway and the xattr fix" "$(grep -q 'Open Anyway' "$cask" && grep -q 'xattr -dr com.apple.quarantine /Applications/Mooring.app' "$cask"; echo $?)"
check "cask no longer suggests right-click Open" "$(! grep -qi 'right-click' "$cask"; echo $?)"
check "cask says Sparkle updates the app" "$(grep -q '^  auto_updates true$' "$cask"; echo $?)"
check "cask quits Mooring on uninstall" "$(grep -q '^  uninstall quit: "dev.mooring.app"$' "$cask"; echo $?)"
check "cask zaps Mooring's folder and preferences" "$(grep -q '^  zap trash: \[$' "$cask" \
    && grep -q '^    "~/Library/Application Support/Mooring",$' "$cask" \
    && grep -q '^    "~/Library/Preferences/dev.mooring.app.plist",$' "$cask" \
    && grep -q '^    "~/Library/Preferences/dev.mooring.windows.plist",$' "$cask" \
    && grep -q '^    "~/Library/Preferences/dev.mooring.clipboard.plist",$' "$cask" \
    && [ "$(grep -c '^    "~/Library/' "$cask")" -eq 4 ]; echo $?)"
check "CI checks the cask parses" "$(grep -q 'ruby -c dist/homebrew/mooring.rb' "$ROOT/.github/workflows/ci.yml"; echo $?)"
if command -v ruby >/dev/null 2>&1; then
    check "cask is valid Ruby" "$(ruby -c "$cask" >/dev/null 2>&1; echo $?)"
fi
check "nothing published (happy path)" "$([ ! -e "$WORK/happy/forbidden.log" ]; echo $?)"

# --- a stale dist is replaced ---------------------------------------
printf 'stale' > "$dist/Mooring-9.9.9.zip"
run_release "$repo" --dry-run --app "$app"
check "rerun replaces the old zip" "$([ "$CODE" -eq 0 ] && [ "$(stat -f%z "$zip")" -gt 5 ]; echo $?)"

# --- a dirty tree is refused ----------------------------------------------------------------------
repo="$(fresh_repo dirty)"; shims dirty >/dev/null
app="$(fixture_app "$WORK/dirty/built" 9.9.9)"
printf 'x' > "$repo/untracked.txt"
run_release "$repo" --dry-run --check-git --app "$app"
check "dirty tree refused" "$([ "$CODE" -ne 0 ] && grep -qi 'not clean' "$WORK/dirty/out"; echo $?)"
check "dirty tree: nothing written" "$([ ! -e "$repo/dist" ]; echo $?)"

# --- an existing tag is refused -------------------------------------------------------------------
repo="$(fresh_repo tagged)"; shims tagged >/dev/null
app="$(fixture_app "$WORK/tagged/built" 9.9.9)"
"$REAL_GIT" -C "$repo" tag v9.9.9
run_release "$repo" --dry-run --check-git --app "$app"
check "existing tag refused" "$([ "$CODE" -ne 0 ] && grep -q 'v9.9.9 already exists' "$WORK/tagged/out"; echo $?)"
check "existing tag: nothing written" "$([ ! -e "$repo/dist" ]; echo $?)"

# --- --dry-run --publish is refused -----------------------------------------------------------------
repo="$(fresh_repo publish)"; shims publish >/dev/null
app="$(fixture_app "$WORK/publish/built" 9.9.9)"
run_release "$repo" --dry-run --publish --app "$app"
check "dry run + publish refused" "$([ "$CODE" -eq 2 ] && grep -q -- '--dry-run --publish is refused' "$WORK/publish/out" && [ ! -e "$repo/dist" ]; echo $?)"
check "dry run + publish ran no gh or git push" "$([ ! -e "$WORK/publish/forbidden.log" ]; echo $?)"

# --- print_publish only prints (a real run can't be tested: it builds and signs) --------------------
. "$RELEASE"
out="$WORK/publish/printed"
PATH="$WORK/publish/bin:$PATH" print_publish 9.9.9 >"$out" 2>&1
check "publish prints the tag and push" "$(grep -q '^git tag v9.9.9 && git push origin v9.9.9$' "$out"; echo $?)"
check "publish prints gh release create" "$(grep -q '^gh release create v9.9.9 dist/Mooring-9.9.9.zip --title ' "$out"; echo $?)"
check "publish prints the appcast step" "$(grep 'gh-pages' "$out" | grep -q . && grep -q 'dist/appcast.xml' "$out"; echo $?)"
check "publish prints the tap step" "$(grep -q 'homebrew-tap' "$out" && grep -q 'dist/homebrew/mooring.rb' "$out"; echo $?)"
check "publish ran no gh or git push" "$([ ! -e "$WORK/publish/forbidden.log" ]; echo $?)"
check "publish created no tag" "$([ -z "$("$REAL_GIT" -C "$repo" tag)" ]; echo $?)"

# --- bad invocations ------------------------------------------------------------------------------
repo="$(fresh_repo bad)"; shims bad >/dev/null
run_release "$repo" --dry-run --app "$WORK/bad/missing/Mooring.app"
check "missing app refused" "$([ "$CODE" -ne 0 ] && grep -q 'No app at' "$WORK/bad/out"; echo $?)"
run_release "$repo" --dry-run
check "dry run without --app refused" "$([ "$CODE" -ne 0 ] && grep -q -- '--app' "$WORK/bad/out"; echo $?)"
run_release "$repo" --bogus
check "unknown option refused" "$([ "$CODE" -eq 2 ] && grep -q 'Usage' "$WORK/bad/out"; echo $?)"
app="$(fixture_app "$WORK/bad/odd" '1.0 "x"')"
run_release "$repo" --dry-run --app "$app"
check "odd version refused" "$([ "$CODE" -ne 0 ] && [ ! -e "$repo/dist" ]; echo $?)"
check "nothing published (bad invocations)" "$([ ! -e "$WORK/bad/forbidden.log" ]; echo $?)"

# --- real runs need CFBundleVersion and LSMinimumSystemVersion (read_build_and_minos is what a real run calls)
app="$(fixture_app "$WORK/bad/nokeys" 9.9.9)"
plutil -remove CFBundleVersion "$app/Contents/Info.plist"
(read_build_and_minos "$app/Contents/Info.plist" 0) >"$WORK/bad/real1" 2>&1
check "real run: missing CFBundleVersion is an error" "$([ $? -ne 0 ] && grep -q 'no CFBundleVersion' "$WORK/bad/real1"; echo $?)"
plutil -insert CFBundleVersion -string 7 "$app/Contents/Info.plist"
plutil -remove LSMinimumSystemVersion "$app/Contents/Info.plist"
(read_build_and_minos "$app/Contents/Info.plist" 0) >"$WORK/bad/real2" 2>&1
check "real run: missing LSMinimumSystemVersion is an error" "$([ $? -ne 0 ] && grep -q 'no LSMinimumSystemVersion' "$WORK/bad/real2"; echo $?)"
plutil -remove CFBundleVersion "$app/Contents/Info.plist"
read_build_and_minos "$app/Contents/Info.plist" 1
check "dry run: missing keys fall back" "$([ "$BUILD" = 1 ] && [ "$MINOS" = 14.0 ]; echo $?)"

# --- a real run refuses an app with no update key or no real signature -----------------------------
# check_update_key and check_signature are what a real run calls after the build.
app="$(fixture_app "$WORK/bad/nokey" 9.9.9)"
(check_update_key "$app/Contents/Info.plist") >"$WORK/bad/key1" 2>&1
check "real run: no SUPublicEDKey is an error" "$([ $? -ne 0 ] && grep -q 'Set MOORING_SPARKLE_PUBLIC_KEY in Config/Local.xcconfig — see docs/RELEASING.md' "$WORK/bad/key1"; echo $?)"
plutil -insert SUPublicEDKey -string ' ' "$app/Contents/Info.plist"
(check_update_key "$app/Contents/Info.plist") >"$WORK/bad/key2" 2>&1
check "real run: a blank SUPublicEDKey is an error" "$([ $? -ne 0 ] && grep -q 'Set MOORING_SPARKLE_PUBLIC_KEY' "$WORK/bad/key2"; echo $?)"
plutil -replace SUPublicEDKey -string 'dGVzdC1wdWJsaWMta2V5' "$app/Contents/Info.plist"
(check_update_key "$app/Contents/Info.plist") >"$WORK/bad/key3" 2>&1
check "real run: an app with a key passes the key check" "$?"

# Ad-hoc (codesign -s -, never a real identity) and unsigned fixtures fail; a shimmed codesign that reports
# an Authority and a TeamIdentifier stands in for a real certificate.
adhoc="$(fixture_app "$WORK/bad/adhoc" 9.9.9)"
chmod +x "$adhoc/Contents/MacOS/Mooring"
codesign -s - "$adhoc" 2>/dev/null
(check_signature "$adhoc") >"$WORK/bad/sig1" 2>&1
check "real run: an ad-hoc signature is an error" "$([ $? -ne 0 ] && grep -q 'Set MOORING_SIGN_IDENTITY' "$WORK/bad/sig1"; echo $?)"
unsigned="$(fixture_app "$WORK/bad/unsigned" 9.9.9)"
(check_signature "$unsigned") >"$WORK/bad/sig2" 2>&1
check "real run: an unsigned app is an error" "$([ $? -ne 0 ] && grep -q 'Set MOORING_SIGN_IDENTITY' "$WORK/bad/sig2"; echo $?)"
signer="$WORK/bad/signer"
mkdir -p "$signer"
printf '#!/bin/sh\nprintf "Authority=Apple Development: Test (TEST000000)\\nTeamIdentifier=TEAM000000\\n" >&2\n' > "$signer/codesign"
chmod +x "$signer/codesign"
(PATH="$signer:$PATH"; check_signature "$unsigned") >"$WORK/bad/sig3" 2>&1
check "real run: a certificate signature passes" "$?"
printf '#!/bin/sh\nprintf "Authority=Apple Development: Test (TEST000000)\\nTeamIdentifier=not set\\n" >&2\n' > "$signer/codesign"
(PATH="$signer:$PATH"; check_signature "$unsigned") >"$WORK/bad/sig4" 2>&1
check "real run: no TeamIdentifier is an error" "$([ $? -ne 0 ] && grep -q 'Set MOORING_SIGN_IDENTITY' "$WORK/bad/sig4"; echo $?)"

# A real run end to end, with `make` shimmed to "build" a fixture: it stops at the key, then at the signature,
# before anything is zipped.
repo="$(fresh_repo real)"; shims real >/dev/null
built="$WORK/real/derived/Build/Products/Release"
cat > "$WORK/real/bin/make" <<SHIM
#!/bin/sh
case "\$*" in
    *build-release*) mkdir -p "$built" && rm -rf "$built/Mooring.app" && ditto "$WORK/real/fixture/Mooring.app" "$built/Mooring.app" ;;
esac
exit 0
SHIM
# sign_update must never run here (it would read the Keychain key): a shim that fails loudly.
printf '#!/bin/sh\necho "sign_update $*" >> "%s/forbidden.log"\nexit 97\n' "$WORK/real" > "$WORK/real/bin/sign_update"
chmod +x "$WORK/real/bin/make" "$WORK/real/bin/sign_update"
fixture="$(fixture_app "$WORK/real/fixture" 9.9.9)"
(cd "$repo" && PATH="$WORK/real/bin:$PATH" DERIVED="$WORK/real/derived" SIGN_UPDATE="$WORK/real/bin/sign_update" bash "$RELEASE") >"$WORK/real/out" 2>&1
check "real run without a key refused before zipping" "$([ $? -ne 0 ] && grep -q 'Set MOORING_SPARKLE_PUBLIC_KEY' "$WORK/real/out" && [ ! -e "$repo/dist" ]; echo $?)"
plutil -insert SUPublicEDKey -string 'dGVzdC1wdWJsaWMta2V5' "$fixture/Contents/Info.plist"
chmod +x "$fixture/Contents/MacOS/Mooring"
codesign -s - "$fixture" 2>/dev/null
(cd "$repo" && PATH="$WORK/real/bin:$PATH" DERIVED="$WORK/real/derived" SIGN_UPDATE="$WORK/real/bin/sign_update" bash "$RELEASE") >"$WORK/real/out" 2>&1
check "real run with an ad-hoc app refused before zipping" "$([ $? -ne 0 ] && grep -q 'Set MOORING_SIGN_IDENTITY' "$WORK/real/out" && [ ! -e "$repo/dist" ]; echo $?)"
check "nothing published (real runs)" "$([ ! -e "$WORK/real/forbidden.log" ]; echo $?)"

# --- the escaping helpers -------------------------------------------------------------------------
check "xml_escape" "$([ "$(xml_escape 'a&b<c>"d'"'"'e')" = 'a&amp;b&lt;c&gt;&quot;d&apos;e' ]; echo $?)"

if [ "$failures" -ne 0 ]; then
    echo "$failures release check(s) failed"
    for out in "$WORK"/*/out; do echo "== $out"; cat "$out"; done
    exit 1
fi
echo "release: all checks passed"

#!/bin/bash
# Tests `make uninstall` in a sandbox: a temporary HOME, a fake INSTALL_DIR and a stub pkill.
# It never touches /Applications, the real ~/.local/bin or a running Mooring.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
# A space in every path checks the recipe's quoting.
WORK="$BASE/make uninstall"
mkdir -p "$WORK"

case "$WORK" in
    /Applications*|"$HOME"/.local*) echo "refusing to run in $WORK"; exit 1 ;;
esac

failures=0

check() { # name, condition result (0 = pass)
    if [ "$2" -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}

# Fresh sandbox per case; prints its path. Contains home/, Applications/Mooring.app and bin/pkill (a stub that logs).
sandbox() {
    local dir="$WORK/$1"
    mkdir -p "$dir/home/.local/bin" "$dir/Applications/Mooring.app/Contents/Helpers" "$dir/bin"
    printf '#!/bin/sh\necho "pkill $*" >> "%s"\n' "$dir/pkill.log" > "$dir/bin/pkill"
    chmod +x "$dir/bin/pkill"
    printf 'binary' > "$dir/Applications/Mooring.app/Contents/Helpers/mooring"
    echo "$dir"
}

# Runs `make uninstall` against a sandbox, with the parent make's flags dropped. Sets CODE.
run_uninstall() {
    local dir="$1"
    env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL HOME="$dir/home" PATH="$dir/bin:$PATH" \
        make -s -C "$ROOT" uninstall HOME="$dir/home" INSTALL_DIR="$dir/Applications" PKILL="$dir/bin/pkill" \
        >"$dir/out" 2>&1
    CODE=$?
}

# makeUninstallRemovesOwnLink: a link into the installed app goes with the app, and Mooring is quit first.
dir="$(sandbox own)"
ln -s "$dir/Applications/Mooring.app/Contents/Helpers/mooring" "$dir/home/.local/bin/mooring"
run_uninstall "$dir"
check "makeUninstallRemovesOwnLink: exits 0" "$([ "$CODE" -eq 0 ]; echo $?)"
check "makeUninstallRemovesOwnLink: link removed" "$([ ! -e "$dir/home/.local/bin/mooring" ] && [ ! -L "$dir/home/.local/bin/mooring" ]; echo $?)"
check "makeUninstallRemovesOwnLink: app removed" "$([ ! -e "$dir/Applications/Mooring.app" ]; echo $?)"
check "makeUninstallRemovesOwnLink: Mooring quit" "$(grep -qx 'pkill -x Mooring' "$dir/pkill.log" 2>/dev/null; echo $?)"
check "makeUninstallRemovesOwnLink: rest of ~/.local/bin kept" "$([ -d "$dir/home/.local/bin" ]; echo $?)"

# A link to some other mooring is someone else's.
dir="$(sandbox elsewhere)"
mkdir -p "$dir/other"
printf 'other' > "$dir/other/mooring"
ln -s "$dir/other/mooring" "$dir/home/.local/bin/mooring"
run_uninstall "$dir"
check "foreign link kept" "$([ "$CODE" -eq 0 ] && [ "$(readlink "$dir/home/.local/bin/mooring")" = "$dir/other/mooring" ]; echo $?)"
check "foreign link: app still removed" "$([ ! -e "$dir/Applications/Mooring.app" ]; echo $?)"

# A sibling whose name only starts with Mooring.app isn't inside it.
dir="$(sandbox sibling)"
mkdir -p "$dir/Applications/Mooring.app.old/Contents/Helpers"
ln -s "$dir/Applications/Mooring.app.old/Contents/Helpers/mooring" "$dir/home/.local/bin/mooring"
run_uninstall "$dir"
check "sibling-app link kept" "$([ -L "$dir/home/.local/bin/mooring" ]; echo $?)"
check "sibling app kept" "$([ -d "$dir/Applications/Mooring.app.old" ]; echo $?)"

# A regular file is never removed.
dir="$(sandbox file)"
printf 'mine' > "$dir/home/.local/bin/mooring"
run_uninstall "$dir"
check "regular file kept" "$([ "$CODE" -eq 0 ] && [ "$(cat "$dir/home/.local/bin/mooring")" = "mine" ]; echo $?)"

# Nothing installed: still succeeds.
dir="$(sandbox nothing)"
rm -rf "$dir/Applications/Mooring.app" "$dir/home/.local"
run_uninstall "$dir"
check "nothing installed: exits 0" "$([ "$CODE" -eq 0 ]; echo $?)"

if [ "$failures" -ne 0 ]; then
    echo "$failures make uninstall check(s) failed"
    for out in "$WORK"/*/out; do echo "== $out"; cat "$out"; done
    exit 1
fi
echo "make uninstall: all checks passed"

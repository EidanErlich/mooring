#!/bin/bash
# Tests Integrations/claude-code-plugin/scripts/mooring-hook against fake `mooring` binaries.
# Each case runs the hook with a controlled PATH, HOME, MOORING_BIN and MOORING_APPLICATIONS_DIR.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
HOOK="$ROOT/Integrations/claude-code-plugin/scripts/mooring-hook"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0

# A fake mooring that records its argv and stdin: $1 = path, $2 = log file.
make_fake() {
    mkdir -p "$(dirname "$1")"
    printf '#!/bin/sh\n{ echo "args: $*"; echo "stdin: $(cat)"; } > "%s"\n' "$2" > "$1"
    chmod +x "$1"
}

# Runs the hook in a clean environment. Usage: run_hook <stdin> [VAR=value ...] -> sets OUT, ERR, CODE.
run_hook() {
    local input="$1"; shift
    OUT="$WORK/out"; ERR="$WORK/err"
    printf '%s' "$input" | env -i "$@" sh "${HOOK_UNDER_TEST:-$HOOK}" Stop >"$OUT" 2>"$ERR"
    CODE=$?
}

check() { # name, condition result (0 = pass)
    if [ "$2" -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}

# Fresh sandbox per case; prints its path. Contains home/, apps/ and bin/.
sandbox() {
    local dir="$WORK/$1"
    mkdir -p "$dir/home" "$dir/apps" "$dir/bin"
    echo "$dir"
}

logged() { grep -q "$2" "$1" 2>/dev/null; }

# 1. MOORING_BIN wins over every other location.
d=$(sandbox envOverrideWins)
make_fake "$d/env-mooring" "$d/log-env"
make_fake "$d/home/.local/bin/mooring" "$d/log-local"
make_fake "$d/bin/mooring" "$d/log-path"
make_fake "$d/apps/Mooring.app/Contents/Helpers/mooring" "$d/log-apps"
run_hook "{}" HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" MOORING_BIN="$d/env-mooring" MOORING_APPLICATIONS_DIR="$d/apps"
logged "$d/log-env" "args: hook Stop"; a=$?
[ ! -e "$d/log-local" ] && [ ! -e "$d/log-path" ] && [ ! -e "$d/log-apps" ]; b=$?
check envOverrideWins $((a + b + CODE))

# 2. ~/.local/bin/mooring beats PATH and /Applications.
d=$(sandbox localBinBeforePath)
make_fake "$d/home/.local/bin/mooring" "$d/log-local"
make_fake "$d/bin/mooring" "$d/log-path"
make_fake "$d/apps/Mooring.app/Contents/Helpers/mooring" "$d/log-apps"
run_hook "{}" HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" MOORING_APPLICATIONS_DIR="$d/apps"
logged "$d/log-local" "args: hook Stop"; a=$?
[ ! -e "$d/log-path" ] && [ ! -e "$d/log-apps" ]; b=$?
check localBinBeforePath $((a + b + CODE))

# 3. PATH beats /Applications.
d=$(sandbox pathBeforeApplications)
make_fake "$d/bin/mooring" "$d/log-path"
make_fake "$d/apps/Mooring.app/Contents/Helpers/mooring" "$d/log-apps"
run_hook "{}" HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" MOORING_APPLICATIONS_DIR="$d/apps"
logged "$d/log-path" "args: hook Stop"; a=$?
[ ! -e "$d/log-apps" ]; b=$?
check pathBeforeApplications $((a + b + CODE))

# 4. A script copied into Mooring.app/Contents/Resources/ClaudePlugin/mooring/scripts finds the app's own helper,
# even when /Applications holds another copy.
d=$(sandbox bundleSiblingFound)
scripts="$d/Mooring.app/Contents/Resources/ClaudePlugin/mooring/scripts"
mkdir -p "$scripts"
cp "$HOOK" "$scripts/mooring-hook"
make_fake "$d/Mooring.app/Contents/Helpers/mooring" "$d/log-bundle"
make_fake "$d/apps/Mooring.app/Contents/Helpers/mooring" "$d/log-apps"
HOOK_UNDER_TEST="$scripts/mooring-hook" run_hook "{}" HOME="$d/home" PATH="/usr/bin:/bin" MOORING_APPLICATIONS_DIR="$d/apps"
logged "$d/log-bundle" "args: hook Stop"; a=$?
[ ! -e "$d/log-apps" ]; b=$?
check bundleSiblingFound $((a + b + CODE))

# 5. Falls back to <applications dir>/Mooring.app/Contents/Helpers/mooring.
d=$(sandbox applicationsFallback)
make_fake "$d/apps/Mooring.app/Contents/Helpers/mooring" "$d/log-apps"
run_hook "{}" HOME="$d/home" PATH="/usr/bin:/bin" MOORING_APPLICATIONS_DIR="$d/apps"
logged "$d/log-apps" "args: hook Stop"; a=$?
check applicationsFallback $((a + CODE))

# 6. The hook's stdin reaches mooring untouched.
d=$(sandbox stdinReachesMooring)
make_fake "$d/bin/mooring" "$d/log-path"
run_hook '{"session_id":"abc"}' HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" MOORING_APPLICATIONS_DIR="$d/apps"
logged "$d/log-path" 'stdin: {"session_id":"abc"}'; a=$?
check stdinReachesMooring $((a + CODE))

# 7. With no mooring anywhere: exit 0, nothing printed.
d=$(sandbox noMooringAnywhereExits0Silently)
run_hook "{}" HOME="$d/home" PATH="/usr/bin:/bin" MOORING_APPLICATIONS_DIR="$d/apps"
[ ! -s "$OUT" ] && [ ! -s "$ERR" ]; a=$?
check noMooringAnywhereExits0Silently $((a + CODE))

# 8. A mooring that prints and fails (a stale or foreign binary) leaves no output and no error exit.
d=$(sandbox foreignMooringIsSilenced)
mkdir -p "$d/bin"
printf '#!/bin/sh\necho "to stdout"\necho "to stderr" >&2\nexit 1\n' > "$d/bin/mooring"
chmod +x "$d/bin/mooring"
run_hook "{}" HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" MOORING_APPLICATIONS_DIR="$d/apps"
[ ! -s "$OUT" ] && [ ! -s "$ERR" ]; a=$?
check foreignMooringIsSilenced $((a + CODE))

# 9. A mooring that can't be executed (a bad interpreter, so exec fails) is silent and exits 0.
d=$(sandbox unrunnableMooringIsSilenced)
mkdir -p "$d/bin"
printf '#!/nonexistent/interpreter\n' > "$d/bin/mooring"
chmod +x "$d/bin/mooring"
run_hook "{}" HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" MOORING_APPLICATIONS_DIR="$d/apps"
[ ! -s "$OUT" ] && [ ! -s "$ERR" ]; a=$?
check unrunnableMooringIsSilenced $((a + CODE))

# 10. Without the event argument the script exits 0 and prints nothing, even with a mooring present.
d=$(sandbox missingArgumentExits0)
make_fake "$d/bin/mooring" "$d/log-path"
OUT="$WORK/out"; ERR="$WORK/err"
env -i HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" MOORING_APPLICATIONS_DIR="$d/apps" sh "$HOOK" </dev/null >"$OUT" 2>"$ERR"
CODE=$?
[ ! -s "$OUT" ] && [ ! -s "$ERR" ] && [ ! -e "$d/log-path" ]; a=$?
check missingArgumentExits0 $((a + CODE))

[ "$failures" -eq 0 ]

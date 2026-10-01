#!/usr/bin/env bash
# Smoke test for the `mooring` command against a running, signed Mooring app.
# Usage: scripts/cli-smoke.sh [path-to-mooring]
# It does not quit the app, so the exit-3 check is manual:
#   quit Mooring, then `mooring status --no-launch` must exit 3.
set -uo pipefail

MOORING="${1:-build/DerivedData/Build/Products/Debug/Mooring.app/Contents/Helpers/mooring}"
if [[ ! -x "$MOORING" ]]; then
    echo "mooring not found or not executable: $MOORING" >&2
    exit 1
fi

passed=0
failed=0

# check <name> <expected-exit> <command…>
check() {
    local name="$1" expected="$2"
    shift 2
    "$@" >/dev/null 2>&1
    local got=$?
    if [[ "$got" -eq "$expected" ]]; then
        echo "PASS $name"
        passed=$((passed + 1))
    else
        echo "FAIL $name (got $got)"
        failed=$((failed + 1))
    fi
}

# Succeeds when `mooring status --json` lists an anchor lease (want=yes) or none (want=no).
anchor_listed() {
    local want="$1" output
    output="$("$MOORING" status --json 2>/dev/null)" || return 2
    local found=1
    if command -v jq >/dev/null 2>&1; then
        jq -e '[.leases[].id | startswith("anchor-")] | any' <<<"$output" >/dev/null 2>&1 && found=0
    else
        grep -q '"id":"anchor-' <<<"$output" && found=0
    fi
    if [[ "$want" == yes ]]; then return "$found"; fi
    [[ "$found" -ne 0 ]]
}

check "status --json" 0 "$MOORING" status --json

"$MOORING" anchor -- sleep 20 >/dev/null 2>&1 &
anchor_pid=$!
sleep 1
check "anchor lease is listed" 0 anchor_listed yes

check "lease acquire" 0 "$MOORING" lease acquire smoke-test --ttl 1m
check "lease release" 0 "$MOORING" lease release smoke-test
check "lease release is idempotent" 0 "$MOORING" lease release smoke-test
check "lid lease is refused" 2 "$MOORING" lease acquire smoke-lid --ttl 1m --level lid
check "bare number duration is a usage error" 1 "$MOORING" on --for 5
check "renew of a missing lease" 1 "$MOORING" lease renew no-such-lease

wait "$anchor_pid" 2>/dev/null
sleep 1
check "anchor lease is gone after it finishes" 0 anchor_listed no

echo "$passed passed, $failed failed"
if [[ "$failed" -gt 0 ]]; then exit 1; fi
exit 0

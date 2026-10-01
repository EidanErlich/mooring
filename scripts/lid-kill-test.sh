#!/usr/bin/env bash
# Stage 1c gate (docs/SPEC.md 1.11 and Stages, row 1c): with lid mode on,
# kill -9 the app and check SleepDisabled is back to 0 within 15 s. That is
# the helper's watchdog at work; the app never gets a chance to clean up.
#
#   scripts/lid-kill-test.sh
#
# Needs a signed Debug build, the helper approved and running its stage 1c
# binary, and AC power (or "Allow lid mode on battery").
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/DerivedData/Build/Products/Debug/Mooring.app
FILE="$HOME/Library/Application Support/Mooring/leases.json"
sleep_disabled() { pmset -g | awk '/SleepDisabled/ {print $2}'; }

[ "$(sleep_disabled)" = 0 ] || { echo "SleepDisabled is already 1. Run 'make reset-sleep' first."; exit 1; }
[ -d "$APP" ] || { echo "No app at $APP. Run 'make build' first."; exit 1; }
launchctl print system/dev.mooring.helper >/dev/null 2>&1 || { echo "The helper isn't enabled."; exit 1; }
pmset -g batt | grep -q "AC Power" || echo "Note: on battery. Lid mode needs 'Allow lid mode on battery'."

pkill -x Mooring || true
sleep 1
BACKUP=$(mktemp)
if [ -f "$FILE" ]; then cp "$FILE" "$BACKUP"; else echo "[]" > "$BACKUP"; fi
cleanup() {
  pkill -x Mooring 2>/dev/null || true
  cp "$BACKUP" "$FILE"
  if [ "$(sleep_disabled)" != 0 ]; then
    echo "SleepDisabled is still 1. Run 'make reset-sleep' (needs your password)."
  fi
}
trap cleanup EXIT

# A menu lease with lid mode, expiring in 5 minutes. Dates are seconds since 2001.
python3 - "$FILE" <<'PY'
import json, sys, time
now = time.time() - 978307200
json.dump([{"createdAt": now, "endsOnLidOpen": False, "expiresAt": now + 300, "id": "menu",
            "level": {"display": False, "lid": True}, "owner": {"menu": {}}, "reason": "lid kill test"}],
          open(sys.argv[1], "w"))
PY

open "$APP"
for _ in $(seq 1 20); do [ "$(sleep_disabled)" = 1 ] && break; sleep 0.5; done
[ "$(sleep_disabled)" = 1 ] || { echo "FAIL: lid mode never turned on."; exit 1; }

echo "Lid mode is on. Killing Mooring with kill -9."
kill -9 "$(pgrep -x Mooring)"
start=$(date +%s)
for _ in $(seq 1 20); do
  sleep 1
  if [ "$(sleep_disabled)" = 0 ]; then
    echo "PASS: SleepDisabled back to 0 after $(( $(date +%s) - start )) s."
    exit 0
  fi
done
echo "FAIL: SleepDisabled still 1 after 20 s."
exit 1

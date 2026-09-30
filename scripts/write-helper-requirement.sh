#!/usr/bin/env bash
# Build phase for MooringHelper (docs/SPEC.md, Engineering decisions → Helper and signing).
# Writes the helper's Info.plist with the only client the helper will accept: the
# Mooring app signed by the same certificate. Xcode sets EXPANDED_CODE_SIGN_IDENTITY
# to that certificate's SHA-1; it is "-" for ad-hoc builds and unset when
# CODE_SIGNING_ALLOWED=NO. Anything else yields a placeholder the helper rejects.
set -euo pipefail

template="$1"
output="$2"
identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"

if [[ "$identity" =~ ^[0-9A-Fa-f]{40}$ ]]; then
  requirement="identifier \"dev.mooring.app\" and certificate leaf = H\"$identity\""
else
  requirement="MOORING_UNSIGNED"
  echo "warning: not signed with a certificate; the helper will refuse all connections"
fi

mkdir -p "$(dirname "$output")"
sed -e "s|@MOORING_CLIENT_REQUIREMENT@|$requirement|" \
    -e "s|@MARKETING_VERSION@|${MARKETING_VERSION:-0}|" \
    -e "s|@CURRENT_PROJECT_VERSION@|${CURRENT_PROJECT_VERSION:-0}|" \
    "$template" > "$output"
plutil -lint -s "$output"

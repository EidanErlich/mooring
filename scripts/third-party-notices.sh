#!/bin/bash
# Writes the license files that ship inside Mooring.app: Mooring's own LICENSE and THIRD_PARTY_NOTICES.md, which
# holds the license of every vendored project (THIRD_PARTY/*/) and every Swift package pinned in
# Config/Package.resolved, taken from the build's package checkouts.
#
# Usage: third-party-notices.sh <package checkouts dir> <dest dir>
#   The Xcode build phase passes <DerivedData>/SourcePackages/checkouts and the app's Contents/Resources.
#   Result: <dest>/LICENSE and <dest>/THIRD_PARTY_NOTICES.md.
#
# It fails (and so fails the build) when a pinned package has no checkout or no license file, or its checkout
# isn't at the pinned revision, so an app is never built with incomplete notices.
set -eu
export LC_ALL=C

[ $# -eq 2 ] || { echo "usage: $0 <package checkouts dir> <dest dir>" >&2; exit 64; }
checkouts="$1"; dest="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
resolved="$ROOT/Config/Package.resolved"

fail() { echo "error: third-party-notices: $*" >&2; exit 1; }
[ -f "$resolved" ] || fail "no $resolved"
[ -f "$ROOT/LICENSE" ] || fail "no $ROOT/LICENSE"
[ -d "$checkouts" ] || fail "no package checkouts at $checkouts (resolve packages first, e.g. make build)"

# A short license name from a license file's opening lines; "see below" when it isn't recognised.
license_name() {
    local head
    head="$(head -n 40 "$1")"
    case "$head" in
        *"GNU GENERAL PUBLIC LICENSE"*"Version 3"*) echo "GPL-3.0" ;;
        *"Apache License"*"Version 2.0"*) echo "Apache-2.0" ;;
        *"BSD 3-Clause"* | *"Neither the name"*) echo "BSD-3-Clause" ;;
        *"Permission is hereby granted, free of charge"*) echo "MIT" ;;
        *) echo "see below" ;;
    esac
}

# The license and notice files at the top of a checkout, in a stable order.
license_files() {
    find "$1" -maxdepth 1 -type f \( -iname 'LICENSE*' -o -iname 'LICENCE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' \) \
        | sort
}

# A field from UPSTREAM.md ("- Repo: …").
upstream_field() {
    sed -n "s/^- $2: //p" "$1" | head -n 1
}

# One license file as a fenced block. Tildes, because no license here contains a line of them.
emit_file() {
    echo
    echo "\`$2\`:"
    echo
    echo '~~~~text'
    cat "$1"
    # A file without a final newline would put the fence on its last line.
    [ -z "$(tail -c 1 "$1")" ] || echo
    echo '~~~~'
}

pin() { plutil -extract "pins.$1.$2" raw -o - "$resolved" 2>/dev/null || true; }

body="$(mktemp)"
table="$(mktemp)"
trap 'rm -f "$body" "$table"' EXIT

# --- vendored code -----------------------------------------------------------------------------------
vendored=0
for dir in "$ROOT"/THIRD_PARTY/*/; do
    name="$(basename "$dir")"
    upstream="$dir/UPSTREAM.md"
    [ -f "$dir/LICENSE" ] || fail "THIRD_PARTY/$name has no LICENSE"
    [ -f "$upstream" ] || fail "THIRD_PARTY/$name has no UPSTREAM.md"
    repo="$(upstream_field "$upstream" Repo)"
    commit="$(upstream_field "$upstream" Commit)"
    license="$(upstream_field "$upstream" License | sed 's/ (see LICENSE in this folder)$//')"
    used="$(upstream_field "$upstream" 'Used for')"
    [ -n "$repo" ] && [ -n "$commit" ] && [ -n "$license" ] || fail "THIRD_PARTY/$name/UPSTREAM.md lacks Repo, Commit or License"
    kind="vendored"
    case "$used" in "reference only"*) kind="reference only (no code copied)" ;; esac
    echo "| $name | $kind | $license | $repo |" >> "$table"
    {
        echo
        echo "### $name"
        echo
        echo "- Source: $repo, commit ${commit%% *}"
        echo "- License: $license"
        [ -z "$used" ] || echo "- Used for: $used"
        emit_file "$dir/LICENSE" LICENSE
    } >> "$body"
    vendored=$((vendored + 1))
done
[ "$vendored" -gt 0 ] || fail "no THIRD_PARTY/*/ folders"

# --- Swift packages --------------------------------------------------------------------------------
count="$(plutil -extract pins raw -o - "$resolved")"
case "$count" in '' | *[!0-9]*) fail "can't read the pins in $resolved" ;; esac
i=0
while [ "$i" -lt "$count" ]; do
    location="$(pin "$i" location)"
    revision="$(pin "$i" state.revision)"
    version="$(pin "$i" state.version)"
    [ -n "$location" ] && [ -n "$revision" ] || fail "pin $i in $resolved has no location or revision"
    name="$(basename "$location" .git)"
    checkout="$checkouts/$name"
    [ -d "$checkout" ] || fail "no checkout for $name at $checkout"
    at="$(git -C "$checkout" rev-parse HEAD 2>/dev/null || true)"
    [ -z "$at" ] || [ "$at" = "$revision" ] || fail "$name is checked out at $at, but $resolved pins $revision"
    files="$(license_files "$checkout")"
    [ -n "$files" ] || fail "$name has no license file in $checkout"
    first="$(echo "$files" | grep -i -v '/NOTICE' | head -n 1)"
    license="$(license_name "${first:-$(echo "$files" | head -n 1)}")"
    pinned="${version:-$revision}"
    echo "| $name | Swift package, $pinned | $license | $location |" >> "$table"
    {
        echo
        echo "### $name"
        echo
        echo "- Source: $location, ${version:+version $version, }revision $revision"
        echo "- License: $license"
        while IFS= read -r file; do
            emit_file "$file" "$(basename "$file")"
        done <<< "$files"
    } >> "$body"
    i=$((i + 1))
done

mkdir -p "$dest"
out="$dest/THIRD_PARTY_NOTICES.md"
{
    echo "# Third-party notices"
    echo
    echo "Mooring is Copyright (C) 2026 Eidan Erlich and is licensed under the GNU General Public License,"
    echo "version 3 only (GPL-3.0-only). The full text is in LICENSE, next to this file."
    echo
    echo "Mooring includes code from the projects below; each one's license and notices follow. The window"
    echo "management is derived from Loop (GPL-3.0), and the clipboard history from Maccy (MIT). Chai is listed"
    echo "because Mooring's keep-awake core is modelled on it; none of its code is copied."
    echo
    echo "This file is generated at build time by scripts/third-party-notices.sh from THIRD_PARTY/ and the"
    echo "Swift packages pinned in Config/Package.resolved."
    echo
    echo "| Project | Kind | License | Source |"
    echo "| --- | --- | --- | --- |"
    cat "$table"
    echo
    echo "## Licenses"
    cat "$body"
} > "$out.tmp"
mv "$out.tmp" "$out"
cp "$ROOT/LICENSE" "$dest/LICENSE"

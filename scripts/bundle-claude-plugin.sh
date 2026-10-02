#!/bin/sh
# Builds the Claude Code plugin copy that ships inside Mooring.app.
# Usage: bundle-claude-plugin.sh <plugin dir> <marketplace template> <dest ClaudePlugin dir>
# Result: <dest>/mooring/ (the plugin) and <dest>/.claude-plugin/marketplace.json.
set -eu

[ $# -eq 3 ] || { echo "usage: $0 <plugin dir> <marketplace template> <dest>" >&2; exit 64; }
src="$1"; template="$2"; dest="$3"

[ -d "$src" ] || { echo "error: plugin folder not found: $src" >&2; exit 66; }
[ -f "$template" ] || { echo "error: marketplace template not found: $template" >&2; exit 66; }

rm -rf "$dest"
mkdir -p "$dest/.claude-plugin"
# ditto keeps the executable bit and copies dotfiles such as .claude-plugin.
ditto "$src" "$dest/mooring"
cp "$template" "$dest/.claude-plugin/marketplace.json"

#!/usr/bin/env bash
# Clones each upstream repo at the commit pinned in docs/SPEC.md (Vendoring)
# into .upstream/<Repo>, which is gitignored. Vendoring copies files from there.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .upstream

pins=(
  "Awayke https://github.com/daemonphantom/Awayke.git b50225198abb1c6e21c4d8da513bbd08fafa6a91"
  "Chai https://github.com/lvillani/chai.git 61ec7d2b0ea1b6f1036c4de1d61a6c95bc79feb9"
  "Loop https://github.com/MrKai77/Loop.git 0ac6d834fb2cb542e62748021a88ee0f6a728fd7"
  "Maccy https://github.com/p0deje/Maccy.git c376789c5d377b7c520b6f6e91f3f3a1aa28640b"
)

for pin in "${pins[@]}"; do
  read -r name url sha <<<"$pin"
  dir=".upstream/$name"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" fetch --quiet origin
  else
    git clone --quiet --filter=blob:none "$url" "$dir"
  fi
  git -C "$dir" -c advice.detachedHead=false checkout --quiet "$sha"
  echo "$name @ $(git -C "$dir" rev-parse --short HEAD)"
done

#!/bin/bash
# Builds a Mooring release into dist/: the zip, its Sparkle signature, the appcast and the Homebrew cask.
# It never publishes anything: --publish only PRINTS the tag, gh and git commands for the owner to run.
#
#   scripts/release.sh                       checks, tests, builds Release, signs (Sparkle key in your Keychain)
#   scripts/release.sh --dry-run --app APP   uses an already-built app; no tests, build or signing
#   scripts/release.sh --publish             a real run that also prints the publishing commands (not with --dry-run)
#   scripts/release.sh --dry-run --check-git --app APP    dry run that still checks the tree and tag
#
# Environment: DERIVED (default build/DerivedData) says where the Release build goes;
# SIGN_UPDATE names Sparkle's sign_update if it is not under build/.../SourcePackages/artifacts.

REPO_URL="https://github.com/EidanErlich/mooring"
TAP_URL="https://github.com/EidanErlich/homebrew-tap"
FEED_URL="https://eidanerlich.github.io/mooring/appcast.xml"

usage() {
    cat >&2 <<USAGE
Usage: scripts/release.sh [--dry-run --app PATH] [--check-git] [--publish]
  --dry-run   use --app, skip make test, the Release build and signing (the appcast signature stays empty)
  --app PATH  a built Mooring.app (required with --dry-run)
  --check-git also check the tree and local tag in a dry run (a real run always does, and asks origin too)
  --publish   print the tag, gh release, appcast and tap commands; runs none of them (not with --dry-run)
USAGE
}

die() { echo "release.sh: $*" >&2; exit 1; }

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

# MARKETING_VERSION from the xcconfigs (Local.xcconfig, included last, wins).
xcconfig_version() {
    local value="" found file
    for file in "$1/Config/Shared.xcconfig" "$1/Config/Local.xcconfig"; do
        [ -f "$file" ] || continue
        found="$(sed -n 's|^MARKETING_VERSION[[:space:]]*=[[:space:]]*\([^[:space:]/]*\).*|\1|p' "$file" | tail -n 1)"
        [ -n "$found" ] && value="$found"
    done
    printf '%s' "$value"
}

plist_value() { # plist, key
    plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

# Sets BUILD and MINOS from the bundle. A real run needs both keys; a dry run (a fixture or CI app) falls back.
read_build_and_minos() { # plist, dry_run (1 or 0)
    BUILD="$(plist_value "$1" CFBundleVersion || true)"
    MINOS="$(plist_value "$1" LSMinimumSystemVersion || true)"
    if [ "$2" -eq 0 ]; then
        [ -n "$BUILD" ] || die "no CFBundleVersion in $1"
        [ -n "$MINOS" ] || die "no LSMinimumSystemVersion in $1"
    else
        [ -n "$BUILD" ] || BUILD=1
        [ -n "$MINOS" ] || MINOS=14.0
    fi
}

# A real release must be able to update itself: the built app needs the Sparkle public key.
check_update_key() { # plist
    local key
    key="$(plist_value "$1" SUPublicEDKey || true)"
    case "$key" in
        *[![:space:]]*) ;;
        *) die "the built app has no SUPublicEDKey, so it could never update itself. Set MOORING_SPARKLE_PUBLIC_KEY in Config/Local.xcconfig — see docs/RELEASING.md" ;;
    esac
}

# A real release is signed with the maintainer's own certificate: not ad-hoc, with an Authority and a team.
check_signature() { # app
    local info
    info="$(codesign -dv "$1" 2>&1 || true)"
    if printf '%s\n' "$info" | grep -q '^Signature=adhoc' \
        || ! printf '%s\n' "$info" | grep -q '^Authority=' \
        || ! printf '%s\n' "$info" | grep -q '^TeamIdentifier=' \
        || printf '%s\n' "$info" | grep -q '^TeamIdentifier=not set'; then
        die "$1 is not signed with a certificate (ad-hoc or unsigned). Set MOORING_SIGN_IDENTITY and MOORING_TEAM in Config/Local.xcconfig — see docs/RELEASING.md"
    fi
}

# Refuses a tag that exists on origin. Not being able to ask (offline, no origin) is a warning, not a pass.
check_remote_tag() { # repo root, version
    local code=0
    git -C "$1" ls-remote --exit-code --tags origin "refs/tags/v$2" >/dev/null 2>&1 || code=$?
    case "$code" in
        0) die "Tag v$2 already exists on origin" ;;
        2) ;;
        *) echo "release.sh: warning: Couldn't check origin for tag v$2 (git ls-remote exited $code); look at the repo's tags yourself" >&2 ;;
    esac
}

find_sign_update() { # repo root
    if [ -n "${SIGN_UPDATE:-}" ]; then
        [ -x "$SIGN_UPDATE" ] || die "SIGN_UPDATE is not executable: $SIGN_UPDATE"
        printf '%s' "$SIGN_UPDATE"
        return
    fi
    local found
    found="$(find "$1/build" -maxdepth 8 -type f -perm -u+x -path '*SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update' 2>/dev/null | head -n 1)"
    [ -n "$found" ] || die "Sparkle's sign_update not found under $1/build/**/SourcePackages/artifacts/sparkle/Sparkle/bin. Build once (make build) so Swift Package Manager fetches Sparkle, or set SIGN_UPDATE=/path/to/sign_update."
    printf '%s' "$found"
}

write_appcast() { # file, version, build, min system, length, signature
    local version build minos length signature pub url notes
    version="$(xml_escape "$2")"; build="$(xml_escape "$3")"; minos="$(xml_escape "$4")"
    length="$(xml_escape "$5")"; signature="$(xml_escape "$6")"
    url="$(xml_escape "$REPO_URL/releases/download/v$2/Mooring-$2.zip")"
    notes="$(xml_escape "$REPO_URL/releases/tag/v$2")"
    pub="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
    cat > "$1" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Mooring</title>
    <link>$(xml_escape "$FEED_URL")</link>
    <description>Mooring updates</description>
    <language>en</language>
    <item>
      <title>Version $version</title>
      <pubDate>$pub</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minos</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$notes</sparkle:releaseNotesLink>
      <enclosure url="$url" sparkle:edSignature="$signature" length="$length" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
APPCAST
}

write_cask() { # file, version, sha256
    cat > "$1" <<CASK
cask "mooring" do
  version "$2"
  sha256 "$3"

  url "$REPO_URL/releases/download/v#{version}/Mooring-#{version}.zip"
  name "Mooring"
  desc "Keep your Mac awake, arrange windows, and keep clipboard history"
  homepage "$REPO_URL"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Mooring.app"

  uninstall quit: "dev.mooring.app"

  zap trash: [
    "~/Library/Application Support/Mooring",
    "~/Library/Preferences/dev.mooring.app.plist",
    "~/Library/Preferences/dev.mooring.windows.plist",
    "~/Library/Preferences/dev.mooring.clipboard.plist",
  ]

  caveats <<~EOS
    Mooring is not notarized. If macOS blocks it on first open, go to
    System Settings > Privacy & Security > Open Anyway, or run:
      xattr -dr com.apple.quarantine /Applications/Mooring.app
  EOS
end
CASK
}

print_publish() { # version
    local v="$1"
    cat <<PUBLISH

# --publish: nothing below has been run. Run these yourself, from the repo root, when you are ready.

# 1. Tag the release and create the GitHub Release with the signed zip.
git tag v$v && git push origin v$v
gh release create v$v dist/Mooring-$v.zip --title "Mooring $v" --generate-notes

# 2. Publish the appcast on the gh-pages branch (GitHub Pages serves $FEED_URL).
#    First time only: create the gh-pages branch and enable Pages for it.
PAGES="\$(mktemp -d)" && git clone --branch gh-pages --single-branch $REPO_URL.git "\$PAGES" \\
  && cp dist/appcast.xml "\$PAGES/appcast.xml" && git -C "\$PAGES" add appcast.xml \\
  && git -C "\$PAGES" commit -m "Appcast for v$v" && git -C "\$PAGES" push origin gh-pages

# 3. Publish the cask in the Homebrew tap.
TAP="\$(mktemp -d)" && git clone $TAP_URL.git "\$TAP" \\
  && mkdir -p "\$TAP/Casks" && cp dist/homebrew/mooring.rb "\$TAP/Casks/mooring.rb" \\
  && git -C "\$TAP" add Casks/mooring.rb && git -C "\$TAP" commit -m "mooring $v" && git -C "\$TAP" push
PUBLISH
}

main() {
    set -eu
    local dry_run=0 publish=0 check_git=0 app=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run=1 ;;
            --publish) publish=1 ;;
            --check-git) check_git=1 ;;
            --app) [ $# -ge 2 ] || { usage; exit 2; }; app="$2"; shift ;;
            -h|--help) usage; exit 0 ;;
            *) usage; exit 2 ;;
        esac
        shift
    done
    if [ "$dry_run" -eq 1 ] && [ "$publish" -eq 1 ]; then
        echo "release.sh: --dry-run --publish is refused: a dry run's appcast is unsigned and must not be published" >&2
        exit 2
    fi
    if [ "$dry_run" -eq 1 ] && [ -z "$app" ]; then
        echo "release.sh: --dry-run needs --app PATH (a built Mooring.app)" >&2
        exit 2
    fi
    [ "$dry_run" -eq 0 ] && [ -n "$app" ] && die "--app only goes with --dry-run (a real run builds its own app)"

    local root derived
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "run this inside the Mooring git repository"
    derived="${DERIVED:-build/DerivedData}"
    local source_version
    source_version="$(xcconfig_version "$root")"

    # Clean tree and unused tag. A dry run skips this unless --check-git asks for it.
    if [ "$dry_run" -eq 0 ] || [ "$check_git" -eq 1 ]; then
        local tag_version="$source_version"
        if [ -n "$app" ] && [ -d "$app" ]; then tag_version="$(plist_value "$app/Contents/Info.plist" CFBundleShortVersionString || true)"; fi
        [ -n "$tag_version" ] || die "cannot read the version (MARKETING_VERSION in Config/Shared.xcconfig)"
        [ -z "$(git -C "$root" status --porcelain)" ] || die "the working tree is not clean; commit or stash first"
        if git -C "$root" rev-parse -q --verify "refs/tags/v$tag_version" >/dev/null; then
            die "tag v$tag_version already exists"
        fi
        # A real run also asks origin, which can have a tag this clone hasn't fetched.
        if [ "$dry_run" -eq 0 ]; then
            check_remote_tag "$root" "$tag_version"
        fi
    fi

    if [ "$dry_run" -eq 0 ]; then
        echo "== make test"
        make -C "$root" test
        echo "== Release build"
        make -C "$root" build-release DERIVED="$derived"
        case "$derived" in /*) app="$derived" ;; *) app="$root/$derived" ;; esac
        app="$app/Build/Products/Release/Mooring.app"
    fi

    [ -d "$app" ] || die "No app at $app"
    local plist="$app/Contents/Info.plist"
    [ -f "$plist" ] || die "No Info.plist in $app"

    # The built bundle is authoritative.
    local version build minos
    version="$(plist_value "$plist" CFBundleShortVersionString)" || die "no CFBundleShortVersionString in $plist"
    read_build_and_minos "$plist" "$dry_run"
    build="$BUILD"; minos="$MINOS"
    case "$version" in
        ""|[!0-9A-Za-z]*|*[!0-9A-Za-z._+-]*) die "unusable version '$version' in $plist" ;;
    esac
    if [ "$dry_run" -eq 0 ] && [ -n "$source_version" ] && [ "$version" != "$source_version" ]; then
        die "the built app says $version but Config says $source_version"
    fi

    if [ "$dry_run" -eq 0 ]; then
        echo "== update key and signature"
        check_update_key "$plist"
        check_signature "$app"
        echo "== codesign verify"
        codesign --verify --deep --strict "$app" || die "codesign verification failed for $app"
    fi

    local dist="$root/dist"
    local zip="$dist/Mooring-$version.zip"
    mkdir -p "$dist/homebrew"
    rm -f "$zip" "$zip.sig" "$dist/appcast.xml" "$dist/homebrew/mooring.rb"

    echo "== zip"
    # --sequesterRsrc keeps extended attributes in __MACOSX/, so a plain `unzip` leaves no ._ files in the app.
    ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
    local length sha
    length="$(stat -f%z "$zip")"
    sha="$(shasum -a 256 "$zip" | awk '{print $1}')"

    local signature=""
    if [ "$dry_run" -eq 0 ]; then
        echo "== sign (Sparkle sign_update, key from your Keychain)"
        local sign_update output signed_length
        sign_update="$(find_sign_update "$root")"
        output="$("$sign_update" "$zip")" || die "sign_update failed; is the Sparkle key in your Keychain (generate_keys)?"
        printf '%s\n' "$output" > "$zip.sig"
        signature="$(printf '%s' "$output" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
        [ -n "$signature" ] || die "could not read the signature from sign_update's output"
        signed_length="$(printf '%s' "$output" | sed -n 's/.* length="\([0-9]*\)".*/\1/p')"
        if [ -n "$signed_length" ] && [ "$signed_length" != "$length" ]; then
            die "sign_update saw $signed_length bytes but the zip is $length"
        fi
    else
        echo "== dry run: not signing; the appcast signature is empty"
    fi

    write_appcast "$dist/appcast.xml" "$version" "$build" "$minos" "$length" "$signature"
    write_cask "$dist/homebrew/mooring.rb" "$version" "$sha"

    echo "Wrote:"
    echo "  $zip ($length bytes, sha256 $sha)"
    [ -f "$zip.sig" ] && echo "  $zip.sig"
    echo "  $dist/appcast.xml"
    echo "  $dist/homebrew/mooring.rb"

    if [ "$publish" -eq 1 ]; then
        print_publish "$version"
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi

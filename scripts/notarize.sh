#!/usr/bin/env bash
# Build, sign with a Developer ID, notarize, staple, zip, and PROVE the Mac
# release. Reproducible from the repo: nothing here lives in one person's
# shell history any more (audit 2026-09-02, L-A10).
#
# Needs, once, in your own Terminal (never in this script, never in git):
#
#   cp .env.example .env            # and put your Team ID in LEDGE_DEVELOPMENT_TEAM
#   xcrun notarytool store-credentials ledge-notary \
#       --apple-id you@example.com --team-id YOURTEAMID
#
# The second command asks for an app-specific password (appleid.apple.com,
# Sign-In and Security, App-Specific Passwords) and stores it in your
# Keychain under the profile name. This script only ever names the profile.
#
# Usage:
#   ./scripts/notarize.sh              build, sign, notarize, staple, zip, verify
#   ./scripts/notarize.sh verify       re-verify an existing build/Ledge.app and zip
#
# Environment (all optional):
#   LEDGE_NOTARY_PROFILE   Keychain profile name (default ledge-notary)
#   LEDGE_SIGN_IDENTITY    full identity string; default is derived from the
#                          Team ID in .env: "Developer ID Application: <name> (<team>)"
#                          is looked up in the keychain by team id.
# Built by Claude (Anthropic).
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="${1:-release}"
PROFILE="${LEDGE_NOTARY_PROFILE:-ledge-notary}"
APP=build/Ledge.app
VERSION="$(tr -d '[:space:]' < VERSION)"
ZIP="build/Ledge-v${VERSION}-macOS.zip"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m  %s\n' "$*"; }
die()  { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

# Team ID from the gitignored .env, same as deploy.sh. Never hardcoded.
if [ -f .env ]; then
    set -a; . ./.env; set +a
fi
TEAM="${LEDGE_DEVELOPMENT_TEAM:-}"
[ -n "$TEAM" ] || die "LEDGE_DEVELOPMENT_TEAM is not set. Copy .env.example to .env and put your Apple Team ID in it."

# The Developer ID identity, found by team id so the name never has to be
# typed or committed.
if [ -z "${LEDGE_SIGN_IDENTITY:-}" ]; then
    LEDGE_SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | grep "($TEAM)" | head -1 \
        | sed 's/^[^"]*"\(.*\)".*$/\1/')"
fi
[ -n "$LEDGE_SIGN_IDENTITY" ] || die "no 'Developer ID Application' certificate for team $TEAM in the keychain. Install it from developer.apple.com > Certificates."

verify_release() {
    say "Verify"
    [ -d "$APP" ] || die "$APP is missing; run ./scripts/notarize.sh first"
    codesign --verify --strict --deep "$APP" || die "codesign verification failed"
    ok "codesign --verify --strict"
    codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q . && ok "entitlements present" || ok "no entitlements (none needed)"
    local flags
    flags="$(codesign -dv "$APP" 2>&1 | grep -o 'flags=0x[0-9a-f]*([^)]*)' || true)"
    echo "$flags" | grep -q runtime || die "hardened runtime flag missing: $flags"
    ok "hardened runtime: $flags"
    xcrun stapler validate "$APP" || die "stapler validate failed: the ticket is not attached"
    ok "stapler validate"
    local verdict
    verdict="$(spctl -a -vvv "$APP" 2>&1 || true)"
    echo "$verdict" | grep -q "source=Notarized Developer ID" || die "spctl did not say Notarized Developer ID:
$verdict"
    ok "spctl: source=Notarized Developer ID"
    local built
    built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
    [ "$built" = "$VERSION" ] || die "built version $built does not match VERSION $VERSION"
    ok "version $built"
    if [ -f "$ZIP" ]; then
        # The zip is what people download. Prove it unpacks to the same
        # bytes we just verified.
        local tmp
        tmp="$(mktemp -d)"
        ditto -x -k "$ZIP" "$tmp"
        diff -rq "$APP" "$tmp/Ledge.app" > /dev/null || die "zip contents differ from $APP"
        rm -rf "$tmp"
        ok "zip unpacks to identical bytes"
        printf '  sha256  %s  %s\n' "$(shasum -a 256 "$ZIP" | cut -d' ' -f1)" "$(basename "$ZIP")"
    fi
}

if [ "$TARGET" = "verify" ]; then
    verify_release
    exit 0
fi

say "Build ${VERSION} (Developer ID, hardened runtime)"
./scripts/build-mac.sh > build/notarize-build.log 2>&1 || { tail -20 build/notarize-build.log; die "build failed, log at build/notarize-build.log"; }
ok "built by build-mac.sh"

# Re-sign with the Developer ID identity, hardened runtime, and a secure
# timestamp. build-mac.sh signs ad hoc for local installs; a notarized
# release needs the real identity and the runtime flag.
codesign --force --deep --timestamp --options runtime \
    --sign "$LEDGE_SIGN_IDENTITY" "$APP" \
    || die "codesign with the Developer ID identity failed"
ok "signed: $LEDGE_SIGN_IDENTITY"

say "Notarize"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
ok "zipped $(basename "$ZIP") ($(du -h "$ZIP" | cut -f1))"
# --wait blocks until Apple answers; typically one to five minutes.
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait \
    || die "notarization was not accepted. Fetch the log with:
  xcrun notarytool history --keychain-profile $PROFILE
  xcrun notarytool log <submission-id> --keychain-profile $PROFILE"
ok "accepted by Apple"

say "Staple"
xcrun stapler staple "$APP" || die "stapling failed"
# The zip must carry the stapled app, so rebuild it after stapling.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
ok "stapled and re-zipped"

verify_release

say "Release"
cat <<EOF
  Upload $ZIP to a GitHub release tagged v${VERSION}, for example:

    gh release create v${VERSION} "$ZIP" --title "Ledge v${VERSION}" --notes-file <notes.md>

  Put the sha256 printed above in the release notes so a download can be
  checked against it.
EOF

#!/usr/bin/env bash
# The version drift gate: every version literal in the repo must equal the
# VERSION file at the root. Version drift has burned two sessions already;
# this script is why it cannot happen silently again. Run by CI on every
# push and pull request; run it locally with: bash scripts/check-version.sh
# Built by Claude (Anthropic).
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
if [ -z "$VERSION" ]; then
    echo "FAIL: the VERSION file is empty"
    exit 1
fi
echo "VERSION file says: $VERSION"

fail=0

# The Mac app's Info.plist (also stamped at build time by build-mac.sh,
# but the committed literal must not drift either).
MAC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' apps/mac/Info.plist)"
if [ "$MAC" != "$VERSION" ]; then
    echo "FAIL: apps/mac/Info.plist CFBundleShortVersionString is $MAC, expected $VERSION"
    fail=1
fi

# Every MARKETING_VERSION in the XcodeGen spec (iOS, watch, both widget targets).
FOUND=0
while IFS= read -r value; do
    FOUND=$((FOUND + 1))
    if [ "$value" != "$VERSION" ]; then
        echo "FAIL: apps/ios/project.yml has MARKETING_VERSION $value, expected $VERSION"
        fail=1
    fi
done < <(grep -o 'MARKETING_VERSION: "[^"]*"' apps/ios/project.yml | sed 's/.*"\(.*\)"/\1/')

if [ "$FOUND" -eq 0 ]; then
    echo "FAIL: no MARKETING_VERSION found in apps/ios/project.yml (did the spec format change?)"
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo ""
    echo "Version drift. Fix: set every value above to match the VERSION file"
    echo "(or bump VERSION if a release is being cut), then re-run this script."
    exit 1
fi

echo "OK: VERSION, apps/mac/Info.plist, and $FOUND project.yml targets all agree on $VERSION"

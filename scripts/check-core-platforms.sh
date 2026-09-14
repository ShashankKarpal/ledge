#!/usr/bin/env bash
# Typecheck LedgeCore against every SDK it ships in: watchOS, iOS, macOS.
#
# Why: LedgeCore compiles into the Watch and iPhone targets, but `swift test`
# and build-mac.sh only ever compile it for macOS. On 2026-09-14 a release
# went out with a call to FileManager.homeDirectoryForCurrentUser, which does
# not exist on watchOS; the Mac build, the tests and CI were all green, and
# the first `deploy.sh ios` was what failed. This check takes a few seconds,
# needs no signing, no xcodegen and no device, and runs in CI.
# Built by Claude (Anthropic).
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
for pair in "watchos:arm64-apple-watchos9.0" "iphoneos:arm64-apple-ios16.0" "macosx:arm64-apple-macos13.0"; do
    sdk="${pair%%:*}"
    target="${pair##*:}"
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    if xcrun swiftc -typecheck -module-name LedgeCore -target "$target" -sdk "$sdk_path" \
        core/Sources/LedgeCore/*.swift > "/tmp/ledge-typecheck-$sdk.log" 2>&1; then
        echo "OK   LedgeCore typechecks for $sdk ($target)"
    else
        echo "FAIL LedgeCore does not typecheck for $sdk ($target):"
        grep -E 'error:' "/tmp/ledge-typecheck-$sdk.log" | head -10
        fail=1
    fi
done

if [ "$fail" -ne 0 ]; then
    echo ""
    echo "A LedgeCore API is missing on one of the platforms it ships on. Fix it"
    echo "before deploy.sh ios or a release; the Mac build cannot see this."
    exit 1
fi

#!/usr/bin/env bash
# Build Ledge.app with nothing but the Xcode Command Line Tools.
# No Xcode project, no dependencies, no network. Built by Claude (Anthropic).
set -euo pipefail

cd "$(dirname "$0")/.."

APP=build/Ledge.app
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"

echo "Building Ledge for ${TARGET}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Compile the shared core and the Mac app together into one binary.
SOURCES=$(find core/Sources/LedgeCore apps/mac/Sources -name '*.swift' | sort)

xcrun swiftc $SOURCES \
    -O \
    -target "$TARGET" \
    -module-name Ledge \
    -o "$APP/Contents/MacOS/Ledge"

cp apps/mac/Info.plist "$APP/Contents/Info.plist"

# Ad hoc signature: runs forever on this Mac, no Apple account involved.
codesign --force --deep --sign - "$APP"

echo ""
echo "Done: $APP"
echo "Run:  open $APP"
echo "Tip:  System Settings > General > Login Items to start Ledge at login."

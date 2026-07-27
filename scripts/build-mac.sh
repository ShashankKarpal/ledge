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

# App icon: compiled from the .iconset at build time, so git holds PNGs and
# never a binary .icns blob.
if [ -d apps/mac/Resources/Ledge.iconset ]; then
    iconutil -c icns apps/mac/Resources/Ledge.iconset \
        -o "$APP/Contents/Resources/AppIcon.icns"
    echo "Icon:  AppIcon.icns"
fi

# Menu bar template glyph (@1x/@2x/@3x). Pure alpha; macOS inverts it for us.
if compgen -G "apps/mac/Resources/MenuBarIconTemplate*.png" > /dev/null; then
    cp apps/mac/Resources/MenuBarIconTemplate*.png "$APP/Contents/Resources/"
fi

# Ad hoc signature: runs forever on this Mac, no Apple account involved.
codesign --force --deep --sign - "$APP"

echo ""
echo "Done: $APP"
echo "Run:  open $APP"
echo "Tip:  System Settings > General > Login Items to start Ledge at login."

#!/usr/bin/env bash
#
# Build Ledge and put it on your devices. One command, no Xcode GUI.
#
#   ./scripts/deploy.sh          Mac, iPhone, and Apple Watch
#   ./scripts/deploy.sh mac      Mac only
#   ./scripts/deploy.sh phone    iPhone only (includes the embedded watch app)
#   ./scripts/deploy.sh watch    Apple Watch only
#   ./scripts/deploy.sh ios      iPhone and Apple Watch
#
# IMPORTANT: do not reinstall the watch app using the toggle in the Watch app
# on your iPhone. That path is for App Store builds. On a development build it
# fails with "This app could not be installed at this time". Toggling it OFF
# also uninstalls it from the watch. Use this script instead.
#
# Built by Claude (Anthropic) for Shashank Karpal.

set -euo pipefail
cd "$(dirname "$0")/.."

# Signing: the Apple Team ID is never committed (see CLAUDE.md). It lives in
# a gitignored .env at the repo root and feeds xcodegen and xcodebuild.
if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi

DD=/tmp/ledge-dd
TARGET="${1:-all}"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m  %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m   %s\n' "$*"; }
die()  { printf '\n\033[31mstopped:\033[0m %s\n\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- mac
deploy_mac() {
    say "Mac"
    ./scripts/build-mac.sh > /tmp/ledge-macbuild.log 2>&1 \
        || { tail -20 /tmp/ledge-macbuild.log; die "Mac build failed, log at /tmp/ledge-macbuild.log"; }
    ok "built"
    pkill -x Ledge 2>/dev/null || true
    sleep 1
    rm -rf /Applications/Ledge.app
    cp -R build/Ledge.app /Applications/Ledge.app
    touch /Applications/Ledge.app
    open /Applications/Ledge.app
    ok "installed in /Applications and relaunched"
}

# ------------------------------------------------------------ discovery
discover_devices() {
    xcrun devicectl list devices --quiet --json-output /tmp/ledge-devices.json 2>/dev/null \
        || die "devicectl could not list devices. Is Xcode installed?"
    /usr/bin/python3 - <<'PY'
import json, shlex
data = json.load(open('/tmp/ledge-devices.json'))
found = {}
for dev in data['result']['devices']:
    hw   = dev.get('hardwareProperties', {})
    name = dev.get('deviceProperties', {}).get('name', '')
    plat = hw.get('platform')
    if plat == 'iOS' and 'IPHONE_ID' not in found:
        found['IPHONE_ID']   = dev['identifier']
        found['IPHONE_UDID'] = hw.get('udid', '')
        found['IPHONE_NAME'] = name or 'iPhone'
    if plat == 'watchOS' and 'WATCH_ID' not in found:
        found['WATCH_ID']   = dev['identifier']
        found['WATCH_NAME'] = name or 'Apple Watch'
for k, v in found.items():
    print(f'{k}={shlex.quote(v)}')
PY
}

# --------------------------------------------------------------- build
build_ios() {
    say "Build"
    [ -n "${LEDGE_DEVELOPMENT_TEAM:-}" ] \
        || die "LEDGE_DEVELOPMENT_TEAM is not set. Copy .env.example to .env in the repo root and put your Apple Team ID in it (find it under Xcode > Settings > Accounts, or developer.apple.com > Membership)."
    if command -v xcodegen > /dev/null; then
        (cd apps/ios && xcodegen generate > /dev/null) && ok "project regenerated"
    fi
    xcodebuild -project apps/ios/Ledge.xcodeproj \
               -scheme Ledge \
               -destination "id=${IPHONE_UDID}" \
               -derivedDataPath "$DD" \
               -allowProvisioningUpdates -quiet build > /tmp/ledge-iosbuild.log 2>&1 \
        || { grep -E 'error:' /tmp/ledge-iosbuild.log | head -20; die "iOS build failed, log at /tmp/ledge-iosbuild.log"; }
    ok "built"
}

# ------------------------------------------------------------- install
install_app() {   # device_id  app_path  label  attempts
    local device="$1" app="$2" label="$3" attempts="${4:-1}"
    [ -d "$app" ] || die "not built yet: $app"
    for i in $(seq 1 "$attempts"); do
        if xcrun devicectl device install app --timeout 120 \
               --device "$device" "$app" > /tmp/ledge-install.log 2>&1; then
            ok "$label"
            return 0
        fi
        if [ "$i" -lt "$attempts" ]; then
            warn "attempt $i of $attempts did not take, retrying"
            sleep 8
        fi
    done
    return 1
}

watch_help() {
    cat <<'EOF'

  The watch refused the tunnel. In order of likelihood:

  1. The watch is not on the same Wi-Fi as this Mac. Check on the watch:
     Settings > Wi-Fi. It must be the same SSID, not a guest or IoT band.
     The watch sometimes sits on Bluetooth only and reports nothing.
  2. It just needs another go. This fails and then succeeds a minute later
     more often than not. Run: ./scripts/deploy.sh watch
  3. Your router has client isolation on, which blocks Mac to watch traffic
     even on one SSID.
  4. Watch on your wrist and unlocked, iPhone unlocked and nearby.

  Do NOT try the toggle in the Watch app on your iPhone. On a development
  build it always fails, and switching it off uninstalls the app.

EOF
}

# ---------------------------------------------------------------- main
case "$TARGET" in
    mac|phone|watch|ios|all) ;;
    *) die "unknown target '$TARGET'. Use: mac, phone, watch, ios, or all" ;;
esac

if [ "$TARGET" = "mac" ] || [ "$TARGET" = "all" ]; then
    deploy_mac
fi

if [ "$TARGET" != "mac" ]; then
    say "Devices"
    eval "$(discover_devices)"
    : "${IPHONE_ID:=}" "${IPHONE_UDID:=}" "${IPHONE_NAME:=iPhone}"
    : "${WATCH_ID:=}"  "${WATCH_NAME:=Apple Watch}"
    [ -n "$IPHONE_ID" ] || die "no iPhone found. Plug it in, unlock it, and trust this Mac."
    ok "iPhone: ${IPHONE_NAME}"
    if [ -n "$WATCH_ID" ]; then
        ok "Watch:  ${WATCH_NAME}"
    else
        warn "no paired Apple Watch visible"
    fi

    build_ios

    PHONE_APP="$DD/Build/Products/Debug-iphoneos/Ledge.app"
    WATCH_APP="$DD/Build/Products/Debug-watchos/LedgeWatch.app"

    say "Install"
    if [ "$TARGET" = "phone" ] || [ "$TARGET" = "ios" ] || [ "$TARGET" = "all" ]; then
        install_app "$IPHONE_ID" "$PHONE_APP" "iPhone" 2 \
            || die "iPhone install failed. Unlock it and try again. Log at /tmp/ledge-install.log"
    fi
    if [ "$TARGET" = "watch" ] || [ "$TARGET" = "ios" ] || [ "$TARGET" = "all" ]; then
        if [ -n "$WATCH_ID" ]; then
            if ! install_app "$WATCH_ID" "$WATCH_APP" "Apple Watch" 4; then
                watch_help
                exit 1
            fi
        else
            warn "skipping watch, none visible to devicectl"
        fi
    fi
fi

say "Done"
echo

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
    MAC_LAUNCH_EPOCH="$(date +%s)"
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

# -------------------------------------------------------------- verify
#
# A reinstall must never be able to leave sync silently broken again. Until
# 2026-09-03 this script printed "Done" the moment devicectl said "installed",
# and it exited 0 with sync dead at least twice. Now every install is followed
# by an end-to-end assertion against the Mac's own copy of the iCloud folder:
#
#   1. Each app writes .ledge/heartbeat-<device>.json on launch (device, time,
#      version). A heartbeat for the platform just installed, stamped AFTER the
#      launch and carrying THIS build's version, proves the app started, the
#      folder grant is real (it wrote), and bytes moved device -> iCloud -> Mac.
#   2. A probe capture appended to capture/drop.md before the phone launches
#      proves the other direction: the phone must read the spool and fold it.
#
# If either assertion cannot be made, the script refuses to print a clean
# "Done" and prints a numbered VERIFY SYNC block instead, exit 2.

LEDGE_ROOT="${LEDGE_ROOT:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Ledge}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-120}"
BUILD_VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo unknown)"
VERIFY_FAILED=0

# Newest heartbeat for a platform, as "epoch version digest device", or nothing.
newest_heartbeat() {   # platform
    /usr/bin/python3 - "$LEDGE_ROOT" "$1" <<'PY'
import glob, json, os, sys
from datetime import datetime, timezone
root, platform = sys.argv[1], sys.argv[2]
best = None
for path in glob.glob(os.path.join(root, ".ledge", "heartbeat-*.json")):
    try:
        beat = json.load(open(path))
    except Exception:
        continue
    if beat.get("platform") != platform:
        continue
    try:
        at = datetime.fromisoformat(beat["at"].replace("Z", "+00:00"))
    except Exception:
        continue
    if at.tzinfo is None:
        at = at.replace(tzinfo=timezone.utc)
    epoch = int(at.timestamp())
    if best is None or epoch > best[0]:
        best = (epoch, beat.get("version", "?"), beat.get("inboxDigest") or "-", beat.get("device", "?"))
if best:
    print(*best)
PY
}

# The Mac's own view of inbox.md, in the same form the apps write.
mac_inbox_digest() {
    shasum -a 256 "$LEDGE_ROOT/inbox.md" 2>/dev/null | cut -c1-16
}

# Wait until a heartbeat for $platform is newer than $since, carries the
# built version, and (when $want_digest is 1) reports the same inbox digest
# this Mac holds right now. Returns 1 on timeout.
#
# Why the clock is the INSTALL start, not the launch call: iOS relaunches a
# foregrounded app by itself the moment devicectl replaces it, so the first
# heartbeat of the new build can predate the script's own launch call
# (observed 2026-09-03: heartbeat 12:41:03, launch 12:41:14).
#
# Why the digest: the probe below can be folded by the Mac's own 300 s drain
# timer, so "probe is in inbox.md" alone does not prove the phone read the
# spool. A phone heartbeat whose digest equals the Mac's current inbox bytes
# proves the phone holds the Mac's bytes, whoever folded them.
await_heartbeat() {   # platform since_epoch label want_digest
    local platform="$1" since="$2" label="$3" want_digest="${4:-0}"
    local deadline=$(( $(date +%s) + VERIFY_TIMEOUT ))
    local line epoch version digest device mac_digest
    while [ "$(date +%s)" -lt "$deadline" ]; do
        line="$(newest_heartbeat "$platform" || true)"
        if [ -n "$line" ]; then
            read -r epoch version digest device <<<"$line"
            if [ "$epoch" -ge "$since" ] && [ "$version" = "$BUILD_VERSION" ]; then
                if [ "$want_digest" -eq 0 ]; then
                    ok "$label heartbeat: $device, v$version, $(( epoch - since ))s after install began"
                    return 0
                fi
                mac_digest="$(mac_inbox_digest)"
                if [ -n "$mac_digest" ] && [ "$digest" = "$mac_digest" ]; then
                    ok "$label heartbeat: $device, v$version, inbox digest $digest matches this Mac ($(( epoch - since ))s after install began)"
                    return 0
                fi
            fi
        fi
        sleep 3
    done
    if [ -n "${line:-}" ]; then
        warn "$label heartbeat did not satisfy the check: newest is $device v$version at $(date -r "$epoch" '+%H:%M:%S') digest $digest; install began $(date -r "$since" '+%H:%M:%S'), built v$BUILD_VERSION, Mac inbox digest $(mac_inbox_digest)"
    else
        warn "$label heartbeat: none found in $LEDGE_ROOT/.ledge"
    fi
    return 1
}

verify_folder_readable() {
    if [ ! -f "$LEDGE_ROOT/inbox.md" ]; then
        warn "cannot read $LEDGE_ROOT/inbox.md from this shell (Full Disk Access for Terminal, or the folder moved). Verification cannot run."
        return 1
    fi
}

verify_mac() {
    say "Verify Mac"
    verify_folder_readable || { VERIFY_FAILED=1; return; }
    if ! await_heartbeat macOS "$MAC_LAUNCH_EPOCH" "Mac"; then
        VERIFY_FAILED=1
    fi
}

verify_phone() {
    say "Verify iPhone"
    verify_folder_readable || { VERIFY_FAILED=1; return; }

    # Mac -> phone probe. One spool line, appended in place (never replaced:
    # the Shortcuts bookmark on drop.md dies if the file identity changes).
    PROBE_TOKEN="deploy-probe-$(date +%H%M%S)"
    local stamp; stamp="$(date '+%Y-%m-%d %H:%M')"
    mkdir -p "$LEDGE_ROOT/capture"
    printf '[[%s · deploy.sh]] %s\n' "$stamp" "$PROBE_TOKEN" >> "$LEDGE_ROOT/capture/drop.md"
    ok "probe $PROBE_TOKEN appended to capture/drop.md"

    # Launch the app so it registers, probes its grant, writes its heartbeat,
    # and drains the spool. Harmless when iOS already relaunched it.
    local launch_epoch; launch_epoch="$(date +%s)"
    if xcrun devicectl device process launch --device "$IPHONE_ID" com.shashankkarpal.ledge > /tmp/ledge-launch.log 2>&1; then
        ok "launched Ledge on ${IPHONE_NAME}"
    else
        warn "could not launch Ledge on the phone (unlocked?). Log at /tmp/ledge-launch.log. Open it by hand now."
    fi

    # Nice-to-have: peek at the app container for a non-empty pending queue.
    # devicectl may refuse; that is informational, never the verdict.
    if xcrun devicectl device info files --device "$IPHONE_ID" \
           --domain-type appDataContainer --domain-identifier com.shashankkarpal.ledge \
           --subdirectory Documents > /tmp/ledge-container.log 2>&1; then
        if grep -q 'pending-captures.md' /tmp/ledge-container.log; then
            warn "the phone still holds Documents/pending-captures.md (captures queued locally)"
        else
            ok "no pending-captures.md in the app container"
        fi
    else
        warn "devicectl cannot list the app container on this OS; skipping that check"
    fi

    # Assertion 1: the new build is alive and can write the folder (phone ->
    # iCloud -> Mac). Clock starts at install, see await_heartbeat.
    if ! await_heartbeat iOS "$IOS_INSTALL_EPOCH" "iPhone" 0; then
        VERIFY_FAILED=1
    fi

    # Assertion 2: the probe leaves the spool and lands in inbox.md. Either
    # device may fold it; this alone proves the spool path, not the phone.
    local deadline=$(( $(date +%s) + VERIFY_TIMEOUT ))
    local folded=0
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if grep -q "$PROBE_TOKEN" "$LEDGE_ROOT/inbox.md" 2>/dev/null \
           && ! grep -q "$PROBE_TOKEN" "$LEDGE_ROOT/capture/drop.md" 2>/dev/null; then
            ok "probe folded into inbox.md $(( $(date +%s) - launch_epoch ))s after launch"
            folded=1
            break
        fi
        sleep 3
    done
    if [ "$folded" -eq 0 ]; then
        warn "probe $PROBE_TOKEN is still in capture/drop.md (or missing from inbox.md) after ${VERIFY_TIMEOUT}s"
        VERIFY_FAILED=1
        return
    fi

    # Assertion 3: Mac -> phone. The phone's heartbeat must report the digest
    # of the inbox this Mac now holds (which contains the probe). That is the
    # phone holding the Mac's bytes, whoever folded them.
    if ! await_heartbeat iOS "$IOS_INSTALL_EPOCH" "iPhone" 1; then
        VERIFY_FAILED=1
    fi
}

verify_block() {
    cat <<EOF

  VERIFY SYNC by hand before trusting this install:

  1. On the iPhone, open Ledge. The folder glyph must be a plain folder, with
     no card above the capture bar. If a card is showing, do what it says.
  2. Tap the refresh arrow beside the folder icon. It must report
     "Up to date" or "N captures folded in", not an error.
  3. Confirm the probe ${PROBE_TOKEN:-<token>} is visible on the phone,
     tagged deploy.sh, and that this Mac command finds it:
       grep -n '${PROBE_TOKEN:-<token>}' "$LEDGE_ROOT/inbox.md"
  4. Capture a line on the iPhone, then on this Mac summon Ledge
     (Option+Space) and confirm it appears tagged iPhone.
  5. Both directions must pass. One direction is not sync.

EOF
}

# ---------------------------------------------------------------- main
case "$TARGET" in
    mac|phone|watch|ios|all) ;;
    *) die "unknown target '$TARGET'. Use: mac, phone, watch, ios, or all" ;;
esac

MAC_LAUNCH_EPOCH=0
IOS_INSTALL_EPOCH=0
PROBE_TOKEN=""
if [ "$TARGET" = "mac" ] || [ "$TARGET" = "all" ]; then
    deploy_mac
    verify_mac
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
    IOS_INSTALL_EPOCH="$(date +%s)"
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

    if [ "$TARGET" = "phone" ] || [ "$TARGET" = "ios" ] || [ "$TARGET" = "all" ]; then
        verify_phone
    fi
fi

if [ "$VERIFY_FAILED" -ne 0 ]; then
    say "Installed, NOT verified"
    verify_block
    exit 2
fi

say "Done: installed and sync verified end to end"
echo

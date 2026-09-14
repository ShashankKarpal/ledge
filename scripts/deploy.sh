#!/usr/bin/env bash
#
# Build Ledge and put it on your devices. One command, no Xcode GUI.
#
#   ./scripts/deploy.sh          Mac, iPhone, and Apple Watch
#   ./scripts/deploy.sh mac      Mac only
#   ./scripts/deploy.sh phone    iPhone only (includes the embedded watch app)
#   ./scripts/deploy.sh watch    Apple Watch only
#   ./scripts/deploy.sh ios      iPhone and Apple Watch
#   ./scripts/deploy.sh verify   prove sync both ways, install nothing
#
# Exit codes: 0 verified; 2 installed but NOT verified (read the VERIFY SYNC
# block); 3 verified but the watch app is stale; 4 refused to install because
# captures were still queued in capture/drop.md.
#
# Every install is followed by verification against the Mac's copy of the
# iCloud folder, so run this from a Terminal with Full Disk Access.
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
    # Ask the running app to quit through AppKit so its save-on-quit runs;
    # SIGTERM is now routed to the same path inside the app, but the polite
    # form costs nothing and works on builds that predate that.
    if pgrep -x Ledge > /dev/null; then
        osascript -e 'tell application "Ledge" to quit' > /dev/null 2>&1 || pkill -x Ledge 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -x Ledge > /dev/null || break
            sleep 0.5
        done
        pkill -x Ledge 2>/dev/null || true
    fi
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
# How long to wait before re-proving sync. Five minutes covers the observed
# gap between a passing verification and the stall that followed it
# (17:04 pass, 17:07 stall). Set SOAK_SECONDS=0 to skip, at your own risk.
SOAK_SECONDS="${SOAK_SECONDS:-300}"
BUILD_VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo unknown)"
PHONE_VERIFIED=0
VERIFY_FAILED=0
# The Mac app's own device label, so its heartbeat is matched by identity and
# not merely by platform.
MAC_DEVICE_LABEL="$(defaults read com.shashankkarpal.ledge.mac deviceLabel 2>/dev/null || scutil --get ComputerName 2>/dev/null || echo Mac)"

# Newest heartbeat for a platform, as "epoch version digest device", or nothing.
# DEVICE_FILTER, when set, additionally requires the heartbeat's device label
# to match it exactly. Without that, verification accepted the newest heartbeat
# from ANY iOS device, so a healthy iPad sitting on the same iCloud account
# could certify an iPhone whose sync was dead (external review, 2026-09-03).
newest_heartbeat() {   # platform
    /usr/bin/python3 - "$LEDGE_ROOT" "$1" "${DEVICE_FILTER:-}" <<'PY'
import glob, json, os, sys
from datetime import datetime, timezone
root, platform = sys.argv[1], sys.argv[2]
wanted = sys.argv[3] if len(sys.argv) > 3 else ""
best = None
for path in glob.glob(os.path.join(root, ".ledge", "heartbeat-*.json")):
    try:
        beat = json.load(open(path))
    except Exception:
        continue
    if beat.get("platform") != platform:
        continue
    if wanted and beat.get("device") != wanted:
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
# Are the two devices in agreement RIGHT NOW? Waits for a heartbeat that is
# recent (within max_age) and whose inbox digest equals this Mac's.
#
# This exists because "newer than instant X" is the wrong question for a soak.
# An idle foregrounded phone writes a heartbeat every 120 seconds, so whether
# one lands after an arbitrary timestamp is close to a coin flip, and twice in
# a row a phone in perfect agreement was reported as a failed soak. Agreement
# is the thing being tested; freshness is only there to prove the stamp is not
# ancient (2026-09-04).
await_agreement() {   # label max_age device
    local label="$1" max_age="$2" DEVICE_FILTER="$3"
    local deadline=$(( $(date +%s) + VERIFY_TIMEOUT ))
    local line epoch version digest device now age mac_digest
    while :; do
        line="$(newest_heartbeat iOS || true)"
        mac_digest="$(mac_inbox_digest)"
        if [ -n "$line" ]; then
            read -r epoch version digest device <<<"$line"
            now="$(date +%s)"
            age=$(( now - epoch ))
            if [ "$age" -le "$max_age" ] && [ "$version" = "$BUILD_VERSION" ] \
               && [ -n "$mac_digest" ] && [ "$digest" = "$mac_digest" ]; then
                ok "$label: $device, v$version, agrees with this Mac on $digest (stamped ${age}s ago)"
                return 0
            fi
        fi
        [ "$(date +%s)" -lt "$deadline" ] || break
        sleep 3
    done
    if [ -n "${line:-}" ]; then
        warn "$label: newest $device heartbeat is v$version, ${age:-?}s old, digest $digest; this Mac holds $mac_digest"
    else
        warn "$label: no heartbeat from $DEVICE_FILTER found"
    fi
    return 1
}

# Cross-device freshness. ONLY safe for the Mac checking its own app, where
# the heartbeat and the comparison clock come from the same machine. Never use
# it for the phone: see the note in verify_phone about clock skew.
await_heartbeat() {   # platform since_epoch label want_digest [device]
    local platform="$1" since="$2" label="$3" want_digest="${4:-0}"
    local DEVICE_FILTER="${5:-}"
    local deadline=$(( $(date +%s) + VERIFY_TIMEOUT ))
    local line epoch version digest device mac_digest
    while [ "$(date +%s)" -lt "$deadline" ]; do
        line="$(newest_heartbeat "$platform" || true)"
        if [ -n "$line" ]; then
            read -r epoch version digest device <<<"$line"
            if [ "$epoch" -ge "$since" ] && [ "$version" = "$BUILD_VERSION" ]; then
                if [ "$want_digest" -eq 0 ]; then
                    ok "$label heartbeat: $device, v$version, $(( epoch - since ))s after the check started"
                    return 0
                fi
                mac_digest="$(mac_inbox_digest)"
                if [ -n "$mac_digest" ] && [ "$digest" = "$mac_digest" ]; then
                    ok "$label heartbeat: $device, v$version, inbox digest $digest matches this Mac ($(( epoch - since ))s after the check started)"
                    return 0
                fi
            fi
        fi
        sleep 3
    done
    if [ -n "${line:-}" ]; then
        warn "$label heartbeat did not satisfy the check: newest is $device v$version at $(date -r "$epoch" '+%H:%M:%S') digest $digest; the check started at $(date -r "$since" '+%H:%M:%S'), built v$BUILD_VERSION, Mac inbox digest $(mac_inbox_digest). If the digests match and only the clock differs, sync is fine and this script is at fault."
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
    if ! await_heartbeat macOS "$MAC_LAUNCH_EPOCH" "Mac" 0 "$MAC_DEVICE_LABEL"; then
        VERIFY_FAILED=1
    fi
}

verify_phone() {
    say "Verify iPhone"
    verify_folder_readable || { VERIFY_FAILED=1; return; }

    # Mac -> phone probe. One spool line, appended in place (never replaced:
    # the Shortcuts bookmark on drop.md dies if the file identity changes).
    #
    # A bare shell append can land in the middle of a drain, which truncates
    # exactly the bytes it consumed and would eat a probe appended a moment
    # earlier. The append therefore goes through NSFileCoordinator, the same
    # lock both apps use (independent review, 2026-09-03).
    PROBE_TOKEN="deploy-probe-$(date +%H%M%S)"
    local stamp; stamp="$(date '+%Y-%m-%d %H:%M')"
    mkdir -p "$LEDGE_ROOT/capture"
    if /usr/bin/osascript -l JavaScript ./scripts/spool-append.js \
        "$LEDGE_ROOT/capture/drop.md" \
        "$(printf '[[%s · deploy.sh]] %s' "$stamp" "$PROBE_TOKEN")" > /dev/null 2>&1
    then
        ok "probe $PROBE_TOKEN appended to capture/drop.md (coordinated)"
    else
        warn "coordinated append failed; probe not written, so the Mac to phone leg cannot be asserted"
        VERIFY_FAILED=1
        return
    fi

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

    # Assertion 1: the phone is alive, running the build we just made, and its
    # writes reach this Mac.
    #
    # NEVER COMPARE A TIMESTAMP FROM ONE DEVICE AGAINST A CLOCK ON ANOTHER.
    # That mistake produced four false failures in two days. The heartbeat's
    # `at` field is written by the phone, from the phone's clock; every
    # "install began" or "check started" value comes from the Mac's clock. A
    # few seconds of ordinary skew between two devices makes any strict
    # ordering between them meaningless, and no amount of reordering the
    # script fixes it (2026-09-04, the fourth instance).
    #
    # What actually proves the thing we care about, using only values that
    # come from the same source:
    #   - the heartbeat carries BUILD_VERSION, which proves the new build ran
    #     and wrote (the version is baked into the binary, not timed);
    #   - its inbox digest equals this Mac's digest, which proves the bytes
    #     agree right now, computed on the Mac from the Mac's own copy;
    #   - its age is merely sanity-checked against a generous window, so an
    #     ancient stamp cannot pass.
    if ! await_agreement "iPhone" 600 "iPhone"; then
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
    # Same rule: agreement, computed from values that share a source. This one
    # is the real Mac to phone proof, because folding the probe CHANGED this
    # Mac's inbox digest, so the phone can only match by having received it.
    if ! await_agreement "iPhone" 600 "iPhone"; then
        VERIFY_FAILED=1
        return
    fi
    PHONE_VERIFIED=1

    # Assertion 4, the SOAK. Every recorded stall began minutes AFTER a
    # verification passed: 2026-09-03 verified at 17:04 and the phone's iCloud
    # stopped moving bytes at 17:07. A point-in-time pass is therefore not
    # evidence that the install is safe, which is the whole lesson of tonight.
    # A second probe after a wait catches a stall that starts in that window.
    # Correlation with reinstalls is established; causation is not, so this
    # measures rather than assumes.
    say "Soak"
    cat <<EOF
  Waiting ${SOAK_SECONDS}s, then re-proving both directions.

  KEEP THE PHONE UNLOCKED AND LEDGE ON SCREEN for this wait. iOS stops the
  app's timers in the background, so a locked phone writes no heartbeat and
  the soak would fail for that reason alone and blame iCloud.
EOF
    sleep "$SOAK_SECONDS"

    # START THE STOPWATCH BEFORE ANYTHING THAT CAUSES A HEARTBEAT. The first
    # version relaunched the app, waited 5 seconds, wrote the probe, and only
    # then took this timestamp, so the heartbeat its own relaunch produced was
    # already 4 seconds too old to satisfy the check. A healthy phone with a
    # matching digest was reported as a failed soak (2026-09-04, and the third
    # bug in this file from measuring against the wrong clock).
    local soak_start; soak_start="$(date +%s)"

    # Bring the app back to the front in case the screen slept anyway; a
    # relaunch is harmless and makes the assertion about sync, not about
    # whether the phone happened to stay awake (external review, 2026-09-03).
    xcrun devicectl device process launch --device "$IPHONE_ID" \
        com.shashankkarpal.ledge > /dev/null 2>&1 || true
    sleep 5

    local soak_token="soak-probe-$(date +%H%M%S)"
    local soak_stamp; soak_stamp="$(date '+%Y-%m-%d %H:%M')"
    if ! /usr/bin/osascript -l JavaScript ./scripts/spool-append.js \
            "$LEDGE_ROOT/capture/drop.md" \
            "$(printf '[[%s · deploy.sh]] %s' "$soak_stamp" "$soak_token")" > /dev/null 2>&1; then
        warn "soak probe could not be written"
        VERIFY_FAILED=1
        return
    fi
    local deadline=$(( $(date +%s) + VERIFY_TIMEOUT ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if grep -q "$soak_token" "$LEDGE_ROOT/inbox.md" 2>/dev/null; then
            break
        fi
        sleep 3
    done
    if ! grep -q "$soak_token" "$LEDGE_ROOT/inbox.md" 2>/dev/null; then
        warn "soak probe $soak_token never reached inbox.md"
        VERIFY_FAILED=1
        return
    fi
    ok "soak probe folded into inbox.md, so the spool path still works"
    # Agreement, not "a write happened after this instant". See await_agreement.
    if await_agreement "iPhone (soak)" 240 "iPhone"; then
        ok "sync still alive $(( $(date +%s) - IOS_INSTALL_EPOCH ))s after install"
        PHONE_VERIFIED=1
    else
        warn "sync passed right after install but not after the soak. Two possible causes, in order: the phone was locked or Ledge was backgrounded during the wait (most likely, and harmless), or this is the 2026-09-03 pattern where the phone's iCloud Drive stops minutes after a reinstall. Re-run ./scripts/deploy.sh verify with the phone awake to tell them apart."
        VERIFY_FAILED=1
    fi
}

verify_block() {
    cat <<EOF

  VERIFY SYNC by hand before trusting this install:

  1. On the iPhone, open Ledge. The folder glyph must be a plain folder, with
     no card above the capture bar. If a card is showing, do what it says.
  2. Tap the refresh arrow beside the folder icon. Any of these is healthy:
       "In sync with ${MAC_DEVICE_LABEL}."
       "In sync with ${MAC_DEVICE_LABEL} as of N minutes ago."
       "Local copy checked, nothing new."      <- normal, not an error
       "N captures folded in."
     These are NOT healthy:
       "... have shown different inboxes for N minutes. iCloud is not delivering."
       anything beginning "Could not" or "Ledge could not"
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
    mac|phone|watch|ios|all|verify) ;;
    *) die "unknown target '$TARGET'. Use: mac, phone, watch, ios, all, or verify" ;;
esac

MAC_LAUNCH_EPOCH=0
IOS_INSTALL_EPOCH=0
PROBE_TOKEN=""
WATCH_FAILED=0

# verify: prove sync both ways against what is already installed. No build,
# no install, nothing replaced. Use it after a watch retry, after an iCloud
# stall, or any time the answer to "is sync actually alive right now" matters.
if [ "$TARGET" = "verify" ]; then
    say "Verify"
    verify_folder_readable || die "cannot read the Ledge folder from this shell. Give Terminal Full Disk Access in System Settings > Privacy and Security."
    eval "$(discover_devices)"
    : "${IPHONE_ID:=}" "${IPHONE_NAME:=iPhone}"
    [ -n "$IPHONE_ID" ] || die "no iPhone visible to devicectl. Unlock it and put it on this Wi-Fi."
    ok "iPhone: ${IPHONE_NAME}"
    # Both clocks start now: nothing was installed, so "newer than install"
    # means "newer than this check".
    MAC_LAUNCH_EPOCH="$(date +%s)"
    IOS_INSTALL_EPOCH="$MAC_LAUNCH_EPOCH"
    # Nudge the Mac app so it stamps a fresh heartbeat for this check.
    pgrep -x Ledge > /dev/null || open -g /Applications/Ledge.app
    verify_phone
    if [ "$VERIFY_FAILED" -ne 0 ]; then
        say "Sync NOT verified"
        verify_block
        exit 2
    fi
    say "Sync verified end to end"
    echo
    exit 0
fi

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

    # REINSTALL CONTAINMENT. Replacing the app while captures are still
    # queued puts the one copy of a thought inside a container that is about
    # to be re-signed, at the exact moment the folder grant dies. Drain first.
    if [ -s "$LEDGE_ROOT/capture/drop.md" ]; then
        warn "capture/drop.md is not empty. Open Ledge on the Mac (Option+Space) to fold those captures in, then run this again."
        say "Refusing to install with captures still in the spool"
        exit 4
    fi

    say "Install"
    IOS_INSTALL_EPOCH="$(date +%s)"
    # Stamp the install so an incident can say how long after a reinstall it
    # began. That number is what settles whether reinstalls are really the
    # trigger, instead of it staying a remembered correlation.
    mkdir -p "$LEDGE_ROOT/.ledge"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$LEDGE_ROOT/.ledge/last-install.txt" 2>/dev/null || true
    if [ "$TARGET" = "phone" ] || [ "$TARGET" = "ios" ] || [ "$TARGET" = "all" ]; then
        install_app "$IPHONE_ID" "$PHONE_APP" "iPhone" 2 \
            || die "iPhone install failed. Unlock it and try again. Log at /tmp/ledge-install.log"
    fi

    # Phone verification runs BEFORE the watch install and is never skipped by
    # a watch failure. The watch reaches the notes only through the phone over
    # WatchConnectivity and cannot touch iCloud at all (docs/spec.md line 189),
    # so a refused watch tunnel says nothing about sync. The first version
    # exited on the watch and left the phone unverified, which is precisely the
    # class of hole this verification stage exists to close (2026-09-03).
    if [ "$TARGET" = "phone" ] || [ "$TARGET" = "ios" ] || [ "$TARGET" = "all" ]; then
        verify_phone
    fi

    # The watch app relays through the phone and never touches iCloud, so a
    # watch-only change must never trigger a phone reinstall. Every recorded
    # sync stall followed a phone reinstall within hours.
    if [ "$TARGET" = "watch" ] || [ "$TARGET" = "ios" ] || [ "$TARGET" = "all" ]; then
        if [ -n "$WATCH_ID" ]; then
            if ! install_app "$WATCH_ID" "$WATCH_APP" "Apple Watch" 4; then
                WATCH_FAILED=1
                watch_help
            fi
        else
            warn "skipping watch, none visible to devicectl"
        fi
    fi
fi

if [ "$VERIFY_FAILED" -ne 0 ]; then
    say "Installed, NOT verified"
    verify_block
    exit 2
fi

if [ "$WATCH_FAILED" -ne 0 ]; then
    if [ "$PHONE_VERIFIED" -eq 1 ]; then
        say "Sync verified end to end; the watch app was NOT updated"
    else
        say "Installed; sync NOT checked; the watch app was NOT updated"
    fi
    cat <<EOF

  The phone and Mac are current and sync is proven in both directions.
  Only the watch app is still on the previous build. Capture on the watch
  keeps working: it relays through the phone, not through iCloud.

  Retry when convenient:  ./scripts/deploy.sh watch
  Re-check sync any time: ./scripts/deploy.sh verify

EOF
    exit 3
fi

if [ "$PHONE_VERIFIED" -eq 1 ]; then
    say "Done: installed and sync verified end to end"
    if [ "$IOS_INSTALL_EPOCH" -ne 0 ]; then
        cat <<'EOF'

  RESTART THE IPHONE when convenient. Both recorded sync stalls followed a
  phone reinstall within hours, and a restart is the only thing that has ever
  cleared one. Causation is unproven, so this is a precaution, not a fix.
  Afterwards, confirm with: ./scripts/deploy.sh verify

EOF
    fi
else
    # mac-only and watch-only runs verify no sync at all. Saying they did was
    # the exact false claim this stage exists to prevent (external review).
    say "Done: installed. Sync was NOT checked on this run"
    echo
    echo "  Only the ${TARGET} target was touched, so nothing proved that notes"
    echo "  still move between devices. Prove it with:"
    echo "      ./scripts/deploy.sh verify"
fi
echo

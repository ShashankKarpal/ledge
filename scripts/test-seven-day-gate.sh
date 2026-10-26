#!/usr/bin/env bash
# Tests for scripts/seven-day-gate.sh, run against small fixture inboxes in a
# temporary folder. Never reads the live inbox: every run passes a fixture
# path, and LEDGE_INBOX is unset. Hand-run like the gate itself (the gate is
# pull-only; neither it nor this test is wired into CI).
#
# Run it:                 bash scripts/test-seven-day-gate.sh
# Against another copy:   GATE=/path/to/seven-day-gate.sh bash scripts/test-seven-day-gate.sh
#                         (DEPLOY=/path/to/deploy.sh likewise)
# Exit code:              0 when every case passes, 1 otherwise, 2 when the
#                         date changed during the run (run it again).
#
# Dates are relative to today, so the cases hold on any day. macOS only
# (BSD date), like the gate. Built by Claude (Anthropic).
set -euo pipefail
unset LEDGE_INBOX

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${GATE:-$HERE/seven-day-gate.sh}"
DEPLOY="${DEPLOY:-$HERE/deploy.sh}"
START_DAY="$(date +%Y-%m-%d)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

day() { date -v-"$1"d +%Y-%m-%d; }

# One day section. Usage: section <days ago> <entry kind>...
# Kinds: real (a capture from the iPhone), probe (what deploy.sh folds in),
# plain (an entry with no device tag), lookalike (another device tag that
# only starts like the probe's).
section() {
    local ago="$1"; shift
    printf '## %s\n\n' "$(day "$ago")"
    local kind
    for kind in "$@"; do
        case "$kind" in
            real)      printf '### 09:00 · iPhone\nA real capture that mentions deploy.sh.\n\n' ;;
            probe)     printf '### 08:00 · deploy.sh\ndeploy-probe-080000\n\n' ;;
            plain)     printf '### 10:00\nAn entry with no device tag.\n\n' ;;
            lookalike) printf '### 11:00 · deploy.sh notes\nA device label that is not the probe.\n\n' ;;
        esac
    done
}

failures=0
# Usage: expect <name> <want run> <want exit> <fixture file>
expect() {
    local name="$1" want_run="$2" want_rc="$3" inbox="$4" out rc run
    set +e
    out="$(bash "$GATE" "$inbox" 2>&1)"
    rc=$?
    set -e
    run="$(printf '%s\n' "$out" | sed -n 's/^Current run: \([0-9][0-9]*\) .*/\1/p')"
    if [ "$run" = "$want_run" ] && [ "$rc" = "$want_rc" ]; then
        echo "ok    $name (run $run, exit $rc)"
    else
        echo "FAIL  $name: want run $want_run exit $want_rc, got run ${run:-none} exit $rc"
        failures=$((failures + 1))
    fi
}

f="$WORK/seven-real.md"
{ for i in 0 1 2 3 4 5 6; do section "$i" real; done; } > "$f"
expect "seven real days open the gate" 7 0 "$f"

f="$WORK/probe-day-in-the-middle.md"
{ for i in 0 1 2; do section "$i" real; done
  section 3 probe
  for i in 4 5 6; do section "$i" real; done; } > "$f"
expect "a probe-only day breaks the run" 3 1 "$f"

f="$WORK/probe-only-today.md"
{ section 0 probe; section 1 real; section 2 real; } > "$f"
expect "a probe-only today is not a capture day" 2 1 "$f"

f="$WORK/probe-fakes-seven.md"
{ section 0 real; section 1 real; section 2 real; section 3 probe
  section 4 real; section 5 real; section 6 real; } > "$f"
expect "a deploy cannot complete a seven-day run" 3 1 "$f"

f="$WORK/probe-and-real.md"
{ section 0 probe real; section 1 real probe; } > "$f"
expect "a day with a probe and a real capture counts" 2 1 "$f"

f="$WORK/other-tags.md"
{ section 0 plain; section 1 lookalike; section 2 real; } > "$f"
expect "untagged and lookalike-tagged entries count" 3 1 "$f"

f="$WORK/probes-only.md"
{ section 0 probe; section 1 probe; } > "$f"
expect "probes alone are a run of zero" 0 1 "$f"

# The probe fixture above copies deploy.sh's tag. Every probe deploy.sh writes
# must still carry exactly that tag, or the gate's skip rule stops matching.
probes="$(grep -c "printf '\[\[%s · " "$DEPLOY" || true)"
tagged="$(grep -c "printf '\[\[%s · deploy\.sh\]\] " "$DEPLOY" || true)"
if [ "$probes" -gt 0 ] && [ "$probes" = "$tagged" ]; then
    echo "ok    every deploy.sh probe carries the deploy.sh tag ($tagged of $probes)"
else
    echo "FAIL  deploy.sh probes and the gate's tag disagree: $tagged of $probes tagged"
    failures=$((failures + 1))
fi

if [ "$(date +%Y-%m-%d)" != "$START_DAY" ]; then
    echo "DATE CHANGED during the run (fixtures and gate saw different days): run again"
    exit 2
fi

if [ "$failures" -eq 0 ]; then
    echo "PASS: all cases"
    exit 0
fi
echo "FAILED: $failures case(s)"
exit 1

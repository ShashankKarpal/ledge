#!/usr/bin/env bash
# The seven-day gate (final-five item 4, roadmap C9): no new feature work
# until the live inbox shows 7 consecutive days of real capture. Pull-only
# and hand-run by design: it displays nothing unprompted, sends nothing,
# nags nobody. It reads entry dates from inbox.md and reports the current
# run of consecutive days that have at least one entry.
#
# Run it:            bash scripts/seven-day-gate.sh
# Other inbox file:  bash scripts/seven-day-gate.sh /path/to/inbox.md
# Exit code:         0 when the gate is open (run >= 7 days), 1 otherwise,
#                    so agent sessions can check it before feature work.
#
# A day counts when it has at least one `### HH:mm` entry under its
# `## yyyy-MM-dd` header. Today counts toward the run if it already has an
# entry; a today with no entry yet does not break the run, because the day
# is not over. macOS only (BSD date). Built by Claude (Anthropic).
set -euo pipefail

GATE_DAYS=7
INBOX="${1:-${LEDGE_INBOX:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Ledge/inbox.md}}"

if [ ! -f "$INBOX" ]; then
    echo "FAIL: no inbox at $INBOX"
    echo "Pass the path as an argument or set LEDGE_INBOX."
    exit 1
fi

# Days that contain at least one entry header, one per line, deduplicated.
DAYS_WITH_ENTRIES="$(awk '
    /^## [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$/ { day = $2; next }
    /^### [0-9]{2}:[0-9]{2}([[:space:]]|$)/ { if (day != "") seen[day] = 1 }
    END { for (d in seen) print d }
' "$INBOX" | sort -u)"

TODAY="$(date +%Y-%m-%d)"
YESTERDAY="$(date -v-1d +%Y-%m-%d)"

has_entries() {
    printf '%s\n' "$DAYS_WITH_ENTRIES" | grep -qx "$1"
}

# Anchor the run at today if today has an entry, else at yesterday (an
# entry-less today is in progress, not a broken run).
if has_entries "$TODAY"; then
    ANCHOR="$TODAY"
elif has_entries "$YESTERDAY"; then
    ANCHOR="$YESTERDAY"
else
    ANCHOR=""
fi

STREAK=0
if [ -n "$ANCHOR" ]; then
    CURSOR="$ANCHOR"
    while has_entries "$CURSOR"; do
        STREAK=$((STREAK + 1))
        CURSOR="$(date -j -f %Y-%m-%d -v-1d "$CURSOR" +%Y-%m-%d)"
    done
fi

echo "Seven-day gate — inbox: $INBOX"
if [ "$STREAK" -eq 0 ]; then
    echo "Current run: 0 days (no entries today or yesterday)."
else
    FIRST="$(date -j -f %Y-%m-%d -v-$((STREAK - 1))d "$ANCHOR" +%Y-%m-%d)"
    echo "Current run: $STREAK consecutive day(s) with captures ($FIRST through $ANCHOR)."
fi

if [ "$STREAK" -ge "$GATE_DAYS" ]; then
    echo "Gate: OPEN. $GATE_DAYS consecutive days of real capture; feature work may proceed."
    exit 0
fi

echo "Gate: CLOSED. Feature work stays parked until the run reaches $GATE_DAYS days."
echo "Bug fixes, capture reliability, and maintenance are always allowed."
exit 1

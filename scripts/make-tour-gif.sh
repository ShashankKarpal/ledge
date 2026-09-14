#!/usr/bin/env bash
# Turn a screen recording into the 30-second README tour: a GIF under 8 MB
# for the README and an MP4 for anywhere that plays video.
#
# You record; this script only converts. Storyboard: docs/TOUR-STORYBOARD.md.
#
# Usage:
#   ./scripts/make-tour-gif.sh path/to/recording.mov [width]
#
# Output:
#   design/tour/ledge-tour.gif   (12 fps, default width 900, target under 8 MB)
#   design/tour/ledge-tour.mp4   (H.264, same trim, for Reddit and the release)
#
# Needs: ffmpeg and gifski (brew install ffmpeg gifski).
# Built by Claude (Anthropic).
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="${1:-}"
WIDTH="${2:-900}"
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "usage: $0 recording.mov [width]"; exit 1; }
command -v ffmpeg > /dev/null || { echo "ffmpeg missing: brew install ffmpeg"; exit 1; }
command -v gifski > /dev/null || { echo "gifski missing: brew install gifski"; exit 1; }

OUT=design/tour
mkdir -p "$OUT"
FRAMES="$(mktemp -d)"
trap 'rm -rf "$FRAMES"' EXIT

echo "Frames at 12 fps, width ${WIDTH}"
ffmpeg -loglevel error -y -i "$SRC" -vf "fps=12,scale=${WIDTH}:-1:flags=lanczos" "$FRAMES/frame_%04d.png"
COUNT="$(ls "$FRAMES" | wc -l | tr -d ' ')"
echo "  $COUNT frames ($(awk "BEGIN{printf \"%.1f\", $COUNT/12}") seconds)"

echo "GIF"
# Quality steps down until the file fits under 8 MB, so the README never
# carries a GIF GitHub refuses to animate.
for quality in 90 80 70 60 50; do
    gifski --fps 12 --quality "$quality" --width "$WIDTH" -o "$OUT/ledge-tour.gif" "$FRAMES"/frame_*.png > /dev/null
    BYTES="$(stat -f %z "$OUT/ledge-tour.gif")"
    echo "  quality $quality: $((BYTES / 1024)) KB"
    [ "$BYTES" -lt $((8 * 1024 * 1024)) ] && break
done
[ "$BYTES" -lt $((8 * 1024 * 1024)) ] || { echo "still over 8 MB; trim the recording or lower the width"; exit 1; }

echo "MP4"
ffmpeg -loglevel error -y -i "$SRC" -vf "scale=${WIDTH}:-2:flags=lanczos" -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart -an "$OUT/ledge-tour.mp4"
echo "  $(du -h "$OUT/ledge-tour.mp4" | cut -f1)"

echo ""
echo "Done: $OUT/ledge-tour.gif and $OUT/ledge-tour.mp4"
echo "The README already references design/tour/ledge-tour.gif; commit both files."

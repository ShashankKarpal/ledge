# The 30-second tour

One GIF at the top of the README, one MP4 for anywhere that plays video. The
hook is motion: eight still screenshots already exist, and none of them shows
the thing Ledge is for, which is the half second between having a thought and
having it written down.

## Before you press record

- Record against a DEMO folder, never the live inbox. Quit Ledge, run
  `defaults write com.shashankkarpal.ledge.mac deviceLabel "MacBook"` if you
  want a generic device name, and point iCloud Drive at a fresh `Ledge` folder
  by moving the real one aside for the recording (move it back afterwards and
  confirm with `./scripts/deploy.sh verify`). Seed the demo inbox with three
  or four plausible entries and two open loops from "yesterday".
- Screen: 1440 x 900 or a 16:10 crop of it; light appearance; hide the
  desktop clutter; menu bar visible (the Step glyph is part of the story).
- Recorder: QuickTime (File, New Screen Recording) or `screencapture -v`.
  No cursor highlight, no clicks sound.
- Keep every action deliberate and slightly slow. GIFs at 12 fps punish fast
  cursor moves.

## Storyboard (about 30 seconds)

| Seconds | On screen | Why it is there |
|---|---|---|
| 0 to 6 | Any app in the foreground. Press Option+Space. The panel slides in from the edge with the cursor already on a fresh timestamped entry. Type one short thought. | The whole pitch in six seconds: one key, already writing. |
| 6 to 10 | Press Esc. The panel tucks away; the foreground app never lost focus. | Zero filing decisions, zero context switch. |
| 10 to 16 | Option+Space again, then Cmd+L. Open Loops lists the unchecked boxes grouped by age. Tick one. | Nothing quietly disappears. |
| 16 to 22 | Cut to the iPhone (screen recording from the phone, or the phone on camera): Back Tap, speak or type a thought, and it appears in the Mac panel a few seconds later. | The same file on every device, no account. |
| 22 to 30 | Cmd+K, type two letters, the fuzzy search finds the entry from step 1. Esc. End on the tucked-away desktop with the menu bar glyph visible. | Find anything, then get out of the way. |

If the phone segment is too much trouble, the tour still works without it:
end on search at about 24 seconds.

## After recording

    brew install ffmpeg gifski        # once
    ./scripts/make-tour-gif.sh ~/Desktop/ledge-tour.mov

The script writes `design/tour/ledge-tour.gif` (12 fps, 900 px wide, steps
quality down until it is under 8 MB so GitHub animates it) and
`design/tour/ledge-tour.mp4`. Commit both. The README already carries the
image slot; the placeholder line comes out in the same commit.

## Checklist before it ships

- [ ] No real entry text is visible anywhere in the recording.
- [ ] No account name, email or absolute path in a window title or a Finder view.
- [ ] GIF under 8 MB, plays in the GitHub README preview in light and dark.
- [ ] MP4 plays with sound off (it has no audio track).
- [ ] The live Ledge folder is back in place and `./scripts/deploy.sh verify` passes.

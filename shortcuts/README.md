# Capture triggers: every path leads to the App Intent

Ledge has exactly one capture action: **Capture to Ledge**, the App Intent built
into the app. Every trigger on this page points at it. The intent writes to the
spool (`capture/drop.md`), never straight into `inbox.md`, and if iCloud is
unreachable it queues the thought locally and delivers it later. No file
bookmarks, no silent failures, nothing to heal.

There used to be a hand-built file-bookmark recipe as the default path. It is
now the documented disaster fallback at the bottom of this page, nothing more.
If you set Ledge up before this change, do the two-minute
[migration](#migrating-from-the-old-recipe) first.

## Siri: nothing to build

With the app installed and launched once, these phrases just work:

- "Capture my thought in Ledge"
- "Capture to Ledge"
- "Add to Ledge"
- "Capture a thought in Ledge"
- "Ledge, capture my thought"

Siri asks "What's the thought?", you dictate, Siri replies "Captured." The same
phrases work on the Apple Watch.

## The wrapper shortcut: "Capture with Ledge"

Back Tap, the Lock Screen, and Control Center bind to shortcuts in your
library, so the intent needs a one-action wrapper. Build it once:

1. Open Shortcuts > **+** > name it `Capture with Ledge`.
   **Do not name it "Capture to Ledge"**: a personal shortcut with the same
   name as the app's Siri phrase shadows the phrase, and that exact collision
   once broke Siri capture for weeks.
2. Add one action: search for **Ledge** > **Capture to Ledge**.
3. Tap the **Thought** field inside the action > select **Ask Each Time**.

Done. Running it prompts for the thought and files it. No folder access
prompts, no file picking.

## The share sheet wrapper: "Share to Ledge"

To capture a link, paragraph, or page from any app's share button:

1. Open Shortcuts > **+** > name it `Share to Ledge`.
2. Add one action: **Ledge** > **Capture to Ledge**.
3. Tap the **Thought** field > select the **Shortcut Input** variable.
4. Open the shortcut's settings (info icon) > turn ON **Show in Share Sheet**.
   Accept: Text, URLs, Safari web pages.

## Bind the triggers (this is where ADHD capture is won)

| Trigger | Where to set it |
|---|---|
| Back Tap (any recent iPhone) | Settings > Accessibility > Touch > Back Tap > Double Tap > **Capture with Ledge** |
| Lock Screen | Long-press the Lock Screen > Customize > add the Shortcuts widget > choose **Capture with Ledge** |
| Control Center (iOS 18+) | Customize Control Center > add Ledge's own **Capture** control, or add the "Shortcut" control pointed at **Capture with Ledge** |
| Home Screen widget | Long-press the Home Screen > add the Ledge widget, or a Shortcuts widget pointed at **Capture with Ledge** |
| Share sheet | Any app > Share > **Share to Ledge** |
| Siri | Say a phrase from the list above; nothing to configure |
| Apple Watch | The native Ledge watch app (dictation), the watch face complications, or Siri on the wrist; all relay through the iPhone with queued delivery |

Recommendation: bind Back Tap and keep the Lock Screen widget. Two reflexes,
zero thought.

## Migrating from the old recipe

If you built the original file-bookmark recipe:

1. In Shortcuts, rename your personal `Capture to Ledge` shortcut to
   `Ledge fallback capture`. This removes the Siri name collision permanently.
   (If you never healed its file bookmark after v0.3.1, delete it instead and
   rebuild it from the fallback section below if you ever need it.)
2. Build `Capture with Ledge` and `Share to Ledge` as above.
3. Re-point every binding in the table above (Back Tap, Lock Screen, Control
   Center, share sheet) away from the old recipe and at the wrappers.
4. Test once: double Back Tap, type a thought, then open the Ledge app and see
   it land in the inbox.

## Disaster fallback: capture with zero apps

Kept for the day the app is gone: this recipe uses only Apple's Shortcuts app,
so it works with Ledge uninstalled, unsigned, or unbuildable. It appends to
`capture/drop.md`; any Ledge app folds the entries into the inbox later.

Know its one weakness before trusting it: the **Append to Text File** action
stores a bookmark to the exact file you picked, and if that bookmark ever
breaks, the shortcut fails silently on every run. (Ledge app versions before
v0.3.1 broke it on every spool drain; since v0.3.1 all spool writes happen in
place, so bookmarks built today stay valid.) If you ever see "the file drop.md
could not be opened", open the shortcut, tap the file chip inside Append to
Text File, and re-pick Ledge > `capture` > `drop.md` once.

Build it as `Ledge fallback capture` (never "Capture to Ledge"; see above):

1. **Ask for Input**. Prompt: `What's the thought?`. Input type: Text.
2. **Current Date** (no changes).
3. **Format Date**. Date: Current Date. Format: Custom. Format string exactly:
   `yyyy-MM-dd HH:mm`
4. **Text**. Content exactly (use the variable chips for the two bracketed
   parts): `[[Formatted Date]] Provided Input`. So the line reads: two literal
   `[` characters, the Formatted Date variable, two literal `]` characters,
   one space, the Provided Input variable. Result example:
   `[[2026-07-19 14:05]] Call Ishan re renewal`.
5. **Append to Text File**. File: browse to your Ledge folder in iCloud Drive
   > `capture` > `drop.md`. Text: the Text variable from step 4. Make New
   Line: ON.

Test it once; approve the folder access prompt the first time. Leave it
unbound: it exists so capture survives the app, not as a daily path.

## How it stays safe

Every path on this page only ever appends to the spool (`capture/drop.md` on
disk, or the intent's local pending queue when iCloud is unreachable), never
touches `inbox.md`. The apps drain the spool with a coordinated read, fold
entries into the inbox with timestamps preserved, deduplicate, and truncate the
spool in place. If iCloud is slow, captures wait; nothing is lost.

# The capture net: iPhone and iPad capture with zero apps

This is Ledge's most important resilience feature. It uses only Apple's Shortcuts app, so it works today, needs no signing, never expires, and keeps capturing even if the Ledge app is not installed or its free-tier signature has lapsed. Captures land in `capture/drop.md`; every Ledge app folds them into the inbox automatically.

Build these once by hand (Shortcuts cannot be safely shipped as files without signing); each takes about two minutes.

## Shortcut 1: "Capture to Ledge" (typed or dictated)

Open Shortcuts > + > name it `Capture to Ledge`.

Add these actions in order:

1. **Ask for Input**. Prompt: `What's the thought?`. Input type: Text. Turn OFF "Allow multiline" only if you prefer one-line speed; otherwise leave on.
2. **Current Date** (no changes).
3. **Format Date**. Date: Current Date. Format: Custom. Format string exactly: `yyyy-MM-dd HH:mm`
4. **Text**. Content exactly (use the variable chips for the two bracketed parts):
   `[[Formatted Date]] Provided Input`
   So the line reads: two literal `[` characters, the Formatted Date variable, two literal `]` characters, one space, the Provided Input variable. Result example: `[[2026-07-19 14:05]] Call Ishan re renewal`.
5. **Append to Text File**. File: browse to your Ledge folder in iCloud Drive > `capture` > `drop.md`. Text: the Text variable from step 4. Make New Line: ON.

Done. Test it once; approve the folder access prompt the first time.

## Shortcut 2: "Capture Share to Ledge" (share sheet)

Duplicate Shortcut 1, rename, then:

1. Delete the Ask for Input action.
2. Tap the shortcut's settings (info icon) > turn ON **Show in Share Sheet**. Accept: Text, URLs, Safari web pages.
3. In the Text action, replace `Provided Input` with the **Shortcut Input** variable.
4. Optional: add a first action **Get Text from Shortcut Input** if you share web pages often (captures the URL and title cleanly).

Now any app's share button can drop a thought, link, or paragraph into your inbox.

## Bind the triggers (this is where ADHD capture is won)

| Trigger | Where to set it |
|---|---|
| Action Button (iPhone 15 Pro and later) | Settings > Action Button > Shortcut > Capture to Ledge |
| Back Tap (any recent iPhone) | Settings > Accessibility > Touch > Back Tap > Double Tap > Capture to Ledge |
| Lock Screen | Long-press the Lock Screen > Customize > add the Shortcuts widget > choose Capture to Ledge |
| Control Center (iOS 18+) | Customize Control Center > add the "Shortcut" control > point it at Capture to Ledge |
| Home Screen widget | Long-press Home Screen > add Shortcuts widget |
| Siri | With the app installed, say "Capture my thought in Ledge" or "Capture to Ledge" (the App Intent). If you keep this manual recipe, rename it to something other than "Capture to Ledge": a personal shortcut with the same name shadows the app's Siri phrase and, if its file bookmark ever breaks, fails silently |
| Apple Watch | The native Ledge watch app (dictation) relays through your iPhone; Shortcuts file actions are unreliable on watchOS, so the watch app is the supported wrist path |

Recommendation: bind Action Button AND Back Tap. Two reflexes, zero thought.

## Dictation-first variant

Duplicate Shortcut 1 and replace **Ask for Input** with **Dictate Text**. Bind that one to the Action Button if voice beats typing for you. Transcription happens on device.

## If you ever see: the file drop.md could not be opened

The Append to Text File action stores a bookmark to the exact file you picked. Before v0.3.1 the apps truncated the spool by atomically replacing it, which gave drop.md a new identity and orphaned every existing bookmark; the shortcut then failed on every run. Since v0.3.1 all spool writes happen in place, so bookmarks stay valid forever. To heal a shortcut built before the fix: open the shortcut, tap the file chip inside Append to Text File, and re-pick Ledge > capture > drop.md once. Preferred setup now that the app carries a one-year signature: point Back Tap and the share sheet at the Capture to Ledge App Intent instead; it uses no file bookmark at all and falls back to a local pending queue when iCloud is unreachable.

## How it stays safe

The shortcut only ever appends to `capture/drop.md`, never touches `inbox.md`. The apps drain the spool with a coordinated read, fold entries into the inbox with timestamps preserved, deduplicate, and truncate the spool. If iCloud is slow, captures wait in the spool file; nothing is lost. If the drop.md file is missing, Append to Text File creates it.

Once the iOS app is installed, you also get the "Add to Ledge" Siri App Intent, which writes the same spool format. The manual shortcuts remain as the layer that never expires.

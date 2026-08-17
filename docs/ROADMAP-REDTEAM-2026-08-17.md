# Roadmap red team, 2026-08-17

Three passes: recover the inherited roadmap, attack the inheritance, attack the replacement. Performed by a kk2 Claude Code session against the repo, the kk1 session logs, the five knowledge dumps, and the live data folder. Usage claims cite the live inbox as observed on 2026-08-17; entry contents are deliberately not quoted.

---

## Pass 1: the roadmap as previously decided

Recovered verbatim where possible, with sources.

**Published roadmap** (README.md, committed in `9ebd0b0`, 2026-08-01):

| Version | Goal | Status then |
|---|---|---|
| v0.5 | "Gentle one-shot reminders handed to Apple Reminders, an iOS Share Sheet extension, TestFlight beta" | Next |
| v0.6 | "Optional local AI adapter (LM Studio, off by default) for inbox summaries and stale-loop surfacing, end-of-day sweep" | Planned |
| Later | "Inline images, focus mode, App Store release, single-source version stamping in CI" | Planned |

**Session-log restatement** (_claude-chats/kk1/2026-08-01_1839_kk1-cowork_ledge-v040-release-audit.md, open threads 3 to 5): same three tiers, with the added rationale that TestFlight is "the item that removes the seven day re-signing wall" (a wall that no longer exists on the maintainer's paid membership; see Pass 2, item 4).

**Spec backlog** (docs/spec.md section 8): M5 rich layer (inline images, KaTeX and mermaid, PDF export, floating windows, focus mode, slash menu, /timer, Vision OCR indexing); M6 optional AI (localhost adapter, tag suggest, summarize, brain-dump-to-checklist, search rerank, FoundationModels probe). The v1 knowledge dump section 7 adds: end-of-day sweep, context breadcrumb, hyperfocus breadcrumb, one-shot gentle reminders.

**Non-code roadmap:**
- Reddit launch: copy banked 2026-07-29 (kk1 log 2026-07-29_2155), still unposted per docs/STATE.md on 2026-08-07.
- Karl as first external tester: open thread since 2026-07-31 (kk1 log 2026-07-31_1853), never confirmed sent.
- VERSION single-source mechanism: flagged in knowledge-dump-v5 section 3.4, "target v0.4", still open.
- The M1 behavior gate: "7 consecutive days where every stray thought goes into Ledge" (knowledge dumps v1 section 11, v2 section 8, v3 section 5). Appears in every dump, was never re-checked in any later artifact.
- Distribution tiers (kk1 log 2026-07-29_2155): Tier 1 notarized GitHub zips now; Tier 2 TestFlight deferred; Tier 3 App Store deferred (would require sandboxing the Mac app and an iCloud container entitlement migration).

---

## Pass 2: attack the inheritance

The evidence base for every attack: real usage after the 2026-08-01 demo reset is five inbox entries across 2026-08-01 to 2026-08-05, then nothing. Every iPhone and Apple Watch entry in the file belongs to the hand-authored demo dataset (knowledge-dump-v4 section 1). One capture sat stranded in the spool from 2026-08-16 until this session. The panel was last summoned 2026-08-07 (`ledge.morningShownDay`). `notes/`, `attic/`, and `assets/` are empty. The maintainer's own Mac runs a superseded build.

**1. The roadmap was written for spectators, not for the owner.** From 2026-07-27 to 2026-08-02, five sessions produced: a full brand identity system, eight curated screenshots with a demo dataset, four notarized releases, a published roadmap "so repo visitors can see direction" (the commit's own words in `9ebd0b0`), Reddit copy drafted twice, an App Store eligibility analysis, and a CHANGELOG. In the same window: the Reddit launch never happened, the one named tester never confirmed received anything, and the owner's real capture flow degraded to five entries and a stranded spool. The audience this work served does not measurably exist; the audience of one was losing the product.

**2. Platform maximalism preceded the habit.** Four platforms, widgets, a Control Center control, and a watch relay shipped before seven consecutive days of real use ever happened. The M1 gate was the project's own stated success criterion in all three early dumps, and it quietly vanished from every artifact after v3. The live inbox proves it was never met: no seven-day streak exists in the file's entire history. The Watch was pulled from v2 to P1 "by owner decision" (spec 3.3, A8), which is to say by enthusiasm; the live record contains zero real Watch captures.

**3. The published roadmap re-promises shipped work.** v0.5's "gentle one-shot reminders handed to Apple Reminders" shipped in v0.3 (`a33f8ac`: "one-shot Send to Reminders"; live code at apps/ios/Sources/Views/InboxView.swift and AppModel.sendToReminders, plus the Mac). A roadmap that does not know what the product already contains was written from the README, not from the backlog.

**4. TestFlight's rationale outlived its own fix.** The 2026-08-01 log justifies TestFlight as removing "the seven day re-signing wall" (a wall that no longer exists: the maintainer's paid membership carries one-year profiles). The paid Developer Program removed that wall on 2026-07-27, and knowledge-dump-v3 section 1 says in bold "do not warn about weekly or 7-day re-signing". The plan carried a dead reason forward, and nobody re-derived the item once its premise died. What TestFlight actually serves is beta testers, of whom there are currently none.

**5. v0.6 AI is a feature for data that does not exist.** Inbox summaries and stale-loop surfacing presuppose volume. Post-reset volume is five entries. An LM Studio localhost adapter also drags a heavyweight external dependency into a product whose README leads with "works out of the box". The spec itself ranks AI as "never a dependency"; the honest reading of the evidence is "never, until volume exists".

**6. Capture reliability never made the roadmap, and it is the product.** The record documents three separate capture-path failures: the inbox self-clobber and the locked-phone conflict loss (knowledge-dump-v2 sections 1 to 2), and the spool bookmark orphaning (`234ff67`). Each was fixed reactively; no roadmap line ever said "capture must be provably un-losable and visibly healthy". Meanwhile the roadmap found room for screenshots, brand, AI, and the App Store. The one promise the app makes (a thought, once captured, lands) had no owner, and a thought is stranded in the spool right now to show for it.

**7. Quiet maintenance debt.** (a) XcodeGen-generated plists bit two sessions (the corruption incident and the silently reverted version fix, dumps v4 and v5) before the durable rule landed. (b) The raw-swiftc Mac build performs no build-setting substitution, so Mac versions are hand-stamped literals; drift is live again today (mac 0.4.1, iOS targets 0.4.0). (c) v0.4.1 removed the knowledge dumps from `docs/` and the history rewrite moved them to `_private/`, so the project's densest reasoning is now invisible to both repo visitors and future repo-only sessions. (d) No bridge handoff for ledge was ever written, despite the household protocol requiring one; this session reconstructed from scratch because of it. (e) The maintainer's Mac runs a build that no longer matches any release artifact (old bundle id), which means releases ship without being dogfooded.

**8. Calm was extended from surfaces to failures.** The design bans (no badges, no counts, no red) govern attention-grabbing UI. They were silently stretched into "the system never tells you anything", which is how a capture can sit in a spool for eleven days with zero indication on any surface. Calm is a UI stance, not an observability policy; the rules never prohibited a muted "1 capture waiting" line.

---

## Pass 3: attack the replacement

Candidates proposed, then attacked. Kills are final for this cycle.

**C1. Capture trust: waiting captures made visible, drains everywhere.** A muted "N captures waiting" line on the Mac panel and iOS inbox when the spool or pending queue is non-empty, a slow background drain timer on the Mac so captures land without a summon, and a core check for stale spool entries.
Attack: this is a bug fix wearing a feature costume, and the drain gap only matters because usage collapsed; a daily summon drains everything. Verdict: the attack fails on the evidence. The app was running the entire eleven days the capture sat stranded; "just summon daily" is the exact assumption that already failed. The failure mode attacks the core promise, and the cost is small (the parser already exists; the UI is one muted line). **SURVIVES**, scope-capped: no new views, no counts anywhere except the in-surface line itself.

**C2. One capture path: every trigger points at the App Intent.** Back Tap, Action Button, Lock Screen, Control Center, share sheet (via a thin Shortcuts wrapper passing Shortcut Input to the intent), and Siri all route to `CaptureIntent`. The file-bookmark recipe is renamed, demoted to documented disaster-fallback, and stops being the default anything.
Attack: the recipe is the "never expires, zero apps" resilience layer and the README's proudest section; demoting it deletes resilience. Verdict: the attack conflates existence with default. The recipe stays documented for the day the app is gone. As a default it has already failed silently once (bookmark orphaning, `234ff67`), and its name collided with the intent so thoroughly that Siri probably ran the broken copy for weeks. Resilience that fails silently is not resilience. **SURVIVES**.

**C3. VERSION single source plus a CI drift gate.** One VERSION file; build-mac.sh stamps the copied plist; project.yml reads it at generate time or CI fails on mismatch.
Attack: infrastructure, not a feature, and there are only four plists; discipline suffices. Verdict: discipline already failed twice and burned a full session plus an independent audit (dumps v4, v5), and drift is live again at this very moment (0.4.1 vs 0.4.0) despite being flagged since 2026-08-01. "Just be careful" has a measured failure rate. Cost is trivial. **SURVIVES**.

**C4. iOS Share Sheet extension** (from v0.5).
Attack: observed demand is one URL capture in the entire live record, and C2's share-sheet wrapper (Shortcut Input into the App Intent, no file bookmark) delivers the same capability for zero new targets, zero App Group plumbing. A native extension is real Xcode surface area serving a flow used once. Verdict: **KILLED**, folded into C2.

**C5. TestFlight beta** (from v0.5).
Attack: its stated rationale died on 2026-07-27 with the paid Developer Program; there are no enrolled testers; the owner's devices deploy for a year via deploy.sh. TestFlight without a tester list is distribution theater. Verdict: **KILLED** until C10 produces actual would-be testers.

**C6. Local AI adapter** (v0.6).
Attack: five entries of post-reset data; summaries of nothing; localhost dependency against the out-of-the-box story; the spec itself says strictly optional. Enthusiasm is the only thing keeping it on the list. Verdict: **KILLED**. Revisit only after the M1 gate has been met and volume exists to summarize.

**C7. End-of-day sweep and Morning Ledge expansion** (v0.6).
Attack: the Morning Ledge last fired 2026-08-07 and by design cannot fire when the panel is never summoned; building an evening twin of an unused morning feature doubles unused surface. Verdict: **KILLED**.

**C8. Inline images, KaTeX, mermaid, PDF export, focus mode, floating windows** (Later and M5).
Attack: `notes/` empty, `assets/` empty, zero named notes ever created. These serve a heavy-editor persona the data says does not exist. Verdict: **KILLED** wholesale.

**C9. The M1 gate reinstated as the release gate.** No new feature work ships until seven consecutive days of real capture, checked by a pull-only script (entry dates from inbox.md), never a badge or streak UI.
Attack one: gamification through the back door, violating the anti-streak ban. Rebuttal: the ban targets coercive UI; a script the owner runs by hand displays nothing unprompted and coerces nothing. Attack two: this is process, not a feature. Conceded, and kept anyway: it is the single highest-leverage item because it is the kill condition for the next imagined feature. Verdict: **SURVIVES**, honestly labeled as process.

**C10. Distribution decision with a deadline.** Execute the Reddit launch (copy has been banked since 2026-07-29) or archive the copy and close the thread. Send the Karl build or drop the thread. One calendar date, two named outcomes each.
Attack: not a feature, and launches motivated by sunk copy are backwards. Rebuttal: it is the oldest open loop in the project and it silently props up C5 and the App Store tier; deciding it (either way) deletes a standing justification for audience-facing work. The attack on "launch because copy exists" is accepted: the default on the deadline is archive, and launching requires a positive reason, such as wanting testers for capture-trust feedback. Verdict: **SURVIVES** as a decision item.

---

## The final five

Only survivors of Pass 3.

| # | Item | Why it survived | Cost | Depends on | You decide |
|---|---|---|---|---|---|
| 1 | Capture trust: waiting-capture visibility and universal drain (C1) | A capture sat stranded 11 days while the app ran; the failure attacks the core promise and the fix is small | ~1 short session: core spool-age check plus one muted line on two surfaces plus a Mac drain timer | Siri fix verified on device (step 0) | Whether a muted in-surface "1 capture waiting" line is acceptable under your no-badges rule |
| 2 | One capture path through the App Intent (C2) | The default capture path failed silently once already and name-collided with itself; consolidation removes the whole failure class | Mostly device-side setup plus shortcuts/README rewrite; code already landed in `4a26a6e` | Nothing | Whether the recipe keeps existing as documented fallback (recommended) or is deleted from the docs entirely |
| 3 | VERSION single source plus CI drift gate (C3) | Version drift has a measured failure rate: two burned sessions, and it is live again today | ~half a session: VERSION file, build-mac stamping, generate-time read, CI check | Nothing | Whether CI failure on drift blocks release tags only or every push |
| 4 | The M1 gate as release gate (C9) | The project's own success metric, silently dropped; it is the kill condition for imagined features | One small script reading inbox.md dates; zero UI | Honest capture data, so items 1 and 2 first | Whether you actually commit to it: no feature merges until the script reports 7 consecutive days |
| 5 | Distribution decision with a deadline (C10) | Oldest open loop; props up TestFlight and App Store thinking while undecided; deciding either way is cheaper than carrying it | One decision, zero code | Ideally after 1 and 2, so what launches is the fixed capture experience | Launch or archive, by a date you pick; default on silence is archive |

## Recommended build order

0. Verify the Siri fix on the iPhone using the test script in STATUS-2026-08-17.md, including renaming the personal "Capture to Ledge" shortcut. Install the current Mac build and re-set the device label for the new defaults domain.
1. Item 2 (one capture path): finish the device-side trigger migration, rewrite shortcuts/README.md around the intent-first setup.
2. Item 1 (capture trust): core stale-spool check with tests, muted waiting line on Mac panel and iOS inbox, Mac background drain timer.
3. Item 3 (VERSION single source and CI gate).
4. Item 5 (distribution decision) on a calendar date.
5. Item 4 (the gate) runs from the day step 0 completes and governs everything after.

## First PR to open

`capture-trust`: item 1 exactly as scope-capped above. Small, testable in LedgeCore, visible on both daily surfaces, and it converts this session's diagnosis into a permanent guarantee. Base it on `4a26a6e`.

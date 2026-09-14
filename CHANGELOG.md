# Changelog

All notable changes to Ledge. History before v0.4.0 was not tracked in this file.

## v0.4.0

- Mac, iOS, iPadOS, and watchOS apps with a shared LedgeCore engine.
- Capture widgets and Control Center control (A7).
- Notarized Mac download. Note: the v0.4.0 artifact identifies as `com.example.ledge.mac`; the bundle id is fixed to `com.shashankkarpal.ledge.mac` for the next release.

## v0.4.1

- Notarized Mac download rebuilt; now identifies as com.shashankkarpal.ledge.mac instead of the com.example placeholder.

- Removed internal knowledge-dump documents from `docs/`; development history now lives in this changelog.
- `project.yml` reads `DEVELOPMENT_TEAM` from the `LEDGE_DEVELOPMENT_TEAM` environment variable (a gitignored `.env`); set your own when building from source.
- Mac bundle id corrected from the `com.example` placeholder.

## Unreleased

### Merge as edit: one thought edited twice is one entry

The file format identifies an entry by day, minute and device, and every
merge used to treat a same-minute, same-device entry with different text as
a second entry. Ticking a checkbox on one device while another held a stale
copy resurrected the unticked twin on that device's next save (the
"completed loops reappear" bug, audit 2026-09-02 L-B3), and a fixed typo
became two entries.

- A new `EditPolicy` on `Inbox.fold`. RELATED texts (equal after normalising
  checkbox marks, one a prefix of the other, sharing at least half their
  lines, or sharing a 60 percent common prefix) collapse into one entry.
  Anything else stays two entries: two Siri captures in one minute are two
  thoughts, and a same-minute entry from a DIFFERENT device is never merged,
  which keeps the 0.5.0 fix for the device-blind merge intact.
- Checkboxes are unioned whichever side wins: a box ticked on either side
  stays ticked. A completion is never undone by a merge.
- Direction is the caller's decision: `saveInbox` merging our newer state
  onto changed disk bytes prefers the incoming text; folding an iCloud
  conflict version (the loser of a race, older by construction) prefers the
  existing text; the Mac editor's recovery journal (an unsaved edit) prefers
  the incoming text; spool drains keep both, always, because captures are
  not edits.

Nine tests, including the two cross-device scenarios end to end through
`saveInbox`: a completed loop survives a stale device's save as exactly one
ticked entry, and a typo fix lands as one entry. 93 tests.

### Save on quit for SIGTERM, and a journal that no longer waits for a failure (Mac)

Two gaps in the editor's last line of defence, found by reading the quit
path after the same class of bug surfaced in a sibling app:

- `applicationWillTerminate` was the only place the panel saved on quit, and
  AppKit never runs it for a signal. `pkill -x Ledge` (what deploy.sh used),
  `launchctl bootout`, and a shutdown that gives up waiting all send SIGTERM,
  whose default disposition ends the process at once. SIGTERM and SIGINT are
  now routed through a DispatchSource into the ordinary `NSApp.terminate`, so
  the panel's `commit()` runs. Proven on the live Mac: the previous build
  answered `kill -TERM` with launchd reporting termination `(2, 15, 15)`, a
  signal death; this build reports `(0, 0, 0)`, a clean exit.
- The recovery journal was written only AFTER a save failed, so text typed
  inside the 0.8 second save debounce had no durable copy anywhere during a
  crash, a power cut, or a SIGKILL. The journal is now written 0.2 seconds
  after every edit, to local disk outside iCloud, and cleared by the
  successful save that follows; a journal write still queued behind a save
  is cancelled so a stale copy can never land after the clear. Inbox mode
  only, because the next summon folds the journal back in as inbox entries.
- `scripts/deploy.sh` asks the running app to quit through AppKit and waits
  up to five seconds before falling back to `pkill`.

### Local versioned backups outside iCloud (Mac)

iCloud is sync, not backup: a bad merge or a stray delete reaches every
device within seconds. The Mac app now keeps dated copies of `inbox.md` and
every attic month file in `~/Library/Application Support/Ledge/backups/`, a
folder iCloud never touches and no repo ever holds.

- Change-driven, never on a timer: a copy is written only when the file's
  bytes differ from the newest copy, detected from the digest the heartbeat
  writer already computes. Identical bytes are never stored twice.
- Verified before it counts: written to a temporary name, read back, digested
  and compared, then renamed into place and recorded in an append-only
  `manifest.jsonl`. A copy that cannot be proven is deleted, not kept.
- Bounded: everything from the last 48 hours, then the newest per day for 30
  days, then the newest per week for six months, then nothing, plus a 200 MB
  hard cap that evicts oldest first. Pruning runs at most once a day and
  never removes the newest copy of any file.
- Names carry a UTC stamp (`inbox-20260914T113653Z-<digest>.md`) so ordering
  survives a time zone change on the machine.
- The Recovery screen shows the count, the newest copy's age and the disk
  used; "Reveal safety copies" opens the folder. There is no restore button:
  the files are plain Markdown, and when a restore action arrives it will
  write into a NEW folder, never over the live one.

Six tests: change detection, byte-identical verification, an unreadable
source storing nothing, hyphenated names round-tripping, 500 synthetic
snapshots over 200 days honouring every tier with the newest surviving, and
the byte cap evicting oldest first. 84 tests.

### Recovery screen on the Mac (observational first)

Right-click the menu bar glyph, then Recovery. One window that answers "is
sync actually alive, and did anything go missing" from what is already on
disk, without asking iCloud for anything:

- Folder: path, reachable, inbox.md size and age, iCloud download state,
  parsed entry and day counts, the 16-character digest every heartbeat quotes.
- Sync: the health line, every device's heartbeat with age, version and
  whether it holds the same bytes as this Mac, unresolved conflict versions,
  the last install stamp.
- Captures: how many wait in the spool, how many the write-ahead capture log
  recorded, how many are unaccounted for (stamp and device only), whether the
  editor recovery journal holds unsaved text.
- Incidents: the last 30 days summarised (count, total, longest, how many
  began within an hour of an install) and the last ten listed.

Safe actions only: Retry filing (the ordinary drain-and-commit path, run now,
with its outcome in words), Reveal folder, Reveal safety copies (the local
folder outside iCloud that holds the capture log and journal), and Copy
diagnostic report. There is no restore action yet; when it arrives it will
write into a NEW folder, never over the live one.

The report is content-free by construction and by test: `RecoveryTests`
plants a phrase in the inbox, the spool, the capture log and the editor
journal and asserts none of them can reach the report text; a second test
takes a byte-level snapshot of the folder before and after gathering and
asserts nothing changed, so the screen can never become load on the transport
it describes. The window refreshes every 20 seconds while open and never
while closed. The "captures are not accounted for" menu row now opens it.
Shared model in LedgeCore (`RecoveryReport`) so the iOS screen, when it
comes, shows the same truth. 78 tests.

### Deploy verification: never compare clocks across devices

Four false failures in two days all came from one mistake, and reordering the
script never fixed it because the mistake was conceptual. The heartbeat's
timestamp is written by the phone from the phone's clock. Every "install
began" or "check started" value is read on the Mac from the Mac's clock. A few
seconds of ordinary skew between two devices makes any strict ordering between
them meaningless. The last run showed it plainly: a phone heartbeat at
10:15:52 against an install the Mac timed at 10:15:55, with the digests
identical.

Every phone assertion now uses `await_agreement`, which compares only values
that share a source: the heartbeat carries the built version (baked into the
binary, not timed), its inbox digest is compared against the Mac's own digest
of its own file, and the age is sanity-checked against a generous window so an
ancient stamp still cannot pass. `await_heartbeat` survives for the Mac
checking its own app, where both values come from the same machine, and now
carries a comment saying it must never be used across devices.

No app code changed, so installed builds are unaffected.

### v0.5.1: the capture log

The last line of defence, and the thing both independent reviews ranked as the
largest reduction in the chance of losing a thought per unit of new code,
ahead of both a storage rewrite and a second sync transport.

- `capture-log.jsonl`, one per device, outside the iCloud folder: iOS in the
  app's own Documents, macOS in Application Support. Every capture is recorded
  there BEFORE anything that can fail, and the line is never deleted.
- Confirmation appends a second line rather than editing the first. Rewriting
  a file in place is the operation behind every data-loss bug in this project,
  so the safety net is forbidden from doing it.
- `unrecovered(comparedTo:)` names captures that were never confirmed and are
  not in the inbox now, with a five minute grace so in-flight captures are not
  reported. The Mac menu shows "N captures are not accounted for" when that
  list is non-empty, and nothing at all when it is empty.
- `exportMarkdown()` reconstructs everything this device ever captured, with
  no app and no AI involved. That is the point: the file is readable and the
  recovery path does not depend on Ledge working.
- Wired into every capture surface that can lose something: iOS in-app
  capture, SpoolWriter (which covers the Siri intent, the widgets and the
  Watch relay), and the Mac quick capture. The Mac panel is covered by its own
  recovery journal from 0.5.0.
- Privacy note, deliberately opposite to `incidents.log`: this file DOES hold
  your capture text, because a log without it could not restore anything. It
  never leaves the device and is not in the synced folder.
- Six tests, including a thirty-way concurrent write and the crash-between-
  record-and-store case the log exists for. 74 tests total.

### v0.5.0: capture durability

Everything in this release is reliability work, which the seven-day gate
exempts. No new capture surfaces were added, deliberately: two review rounds
(an external one via Codex, and a fresh-context adversarial pass) found that
the existing capture paths could lose a thought, and adding a new producer on
top of that would have multiplied the problem. Dictation, Claude capture, a
native share extension and a README video are all deferred or killed for now,
with reasons recorded in the roadmap notes.

**The capture-loss bug, which predates all of this.** `drainSpool` emptied
`capture/drop.md` and recorded the delivery ids BEFORE any caller saved
`inbox.md`, and `saveInbox` throws by design when iCloud has changed the file
underneath it, which is exactly when a drain is likely. One Mac call site
swallowed that save with `try?`. A watch capture could therefore end up in
neither file, with its id already marked delivered so the retry was dropped
too. `drainSpool` now returns a batch the caller must `commit()` after a
successful save, and all five call sites were changed. Covered by a test that
fails against the old ordering.

**Every capture write is now one coordinated transaction.** `SpoolWriter`,
the pending queue and the flush path all did read-modify-write across separate
coordination blocks, which is not a lock: two App Intents, or an Intent and
the watch relay, could read the same bytes and the second write would erase
the first capture. All of them now append inside a single coordinated block,
in place, preserving the file identity the Shortcuts bookmark depends on.
A test runs 40 concurrent appends and asserts that every one survives.

**Capture surfaces tell the truth.** `SpoolWriter.append` returns where the
capture landed (shared spool, local queue, or nowhere). The Siri intent says
which of the three happened instead of always answering "Captured." The watch
relay acknowledges only after the write is durable, so it keeps retrying
otherwise. The iOS capture bar keeps your text on screen instead of clearing
the field and showing a checkmark over a capture that reached nothing.

**The Mac editor keeps a local recovery journal.** A failed save used to leave
the words only in an NSTextView, so quitting or a resummon that reloaded from
disk took them with it. Failed saves now write the text outside the iCloud
folder, the next summon folds it back in and says so, and a successful save
clears it.

**Other data-loss paths closed:** `truncateSpool` no longer blanks a spool it
could not read; the save-merge no longer discards text typed above the first
day header; iCloud conflict versions are only marked resolved once they have
been read AND the merged result has been written; the read stamp is taken
inside the coordination block, so a write landing mid-read can no longer make
the merge guard skip and clobber the other device's bytes; the day-header
leniency added yesterday is now restricted to punctuation-only damage, because
a wider rule let a typed line like `## 2026-01-15 planning` tear an entry in
half; and the duplicate-day merge uses a device-aware key, since the old one
deleted a real capture whenever two devices wrote the same short text in the
same minute.

**Sync health corrections.** A fault set by the heartbeat write was being
cleared by the same pass that set it, leaving the app disconnected, silent and
looking healthy. A transient iCloud write error was being reported as "your
folder access ended". The Mac's hourly idle heartbeat sat outside the
15-minute window the disagreement check trusts, so the warning built for the
2026-09-03 stall could not fire and "Up to date with MacBook M4" was
unreachable; the Mac's cadence is now adaptive (10 minutes while a peer is
active, hourly otherwise).

**The incident log.** `.ledge/incidents.log`: a bounded, content-free record of
when sync was observably broken, with start, end, observer, peer, app version
and how long after an install it began. It exists because the decision about
whether to build a second sync transport was resting on two remembered stalls,
and nothing in the app could count them. No capture text is ever written to it.

**Deploy.** Verification now matches heartbeats by device identity, not just
platform: a healthy iPad could previously certify an iPhone whose sync was
dead. `mac` and `watch` targets no longer claim "sync verified end to end"
having verified no sync at all. The script refuses to install while captures
are still queued in the spool, stamps the install time so incidents can be
dated against it, tells you to keep the phone awake during the soak, relaunches
the app before the soak assertion, and recommends a phone restart afterwards.
New `verify` target proves sync both ways without installing anything.

### Self red team (0.4.4, 2026-09-03 night)

An adversarial pass over the 0.4.3 tree, on the principle that the author had
already shipped two regressions the same day. Findings are the author's own;
an external pass (Codex) was attempted and its backend returned 404 after one
successful earlier run, so this round had no second reader. Four defects,
all in the monitoring added hours earlier:

- WRITE PROBE CHURN. `probeWriteAccess` created and deleted a uniquely named
  `.probe-<uuid>` file in `.ledge/` on every connect and every explicit
  refresh: two iCloud events each time, for information that was thrown away
  immediately. It is now the heartbeat write, which was already required,
  already throws on a dead grant, and replaces one file instead of adding two
  events. The same lesson as the 5-minute heartbeat, found in a second place.
- THE DISAGREEMENT CLOCK OUTLIVED ITS MISMATCH. It was persisted as a bare
  date, and the iOS container survives a reinstall, so an unrelated mismatch
  days later would have inherited the old clock and reported "different
  inboxes for 3 days" on first sight. The clock is now keyed to the specific
  mismatch (peer device plus both digests) and bounded, so a new mismatch
  starts a new clock.
- THE DEPLOY PROBE TRUNCATED THE SPOOL BEFORE REWRITING IT. `drop.md` can hold
  captures no device has folded yet; truncate-then-write opens a window where
  a failure leaves the file empty and those captures are gone. It appends now,
  which also preserves the inode the Shortcuts bookmark depends on. Two JXA
  bugs found while testing it: `initWithFilePresenter(null)` sends NSNull, and
  a seek return value is not usable as a JavaScript number, which had silently
  skipped the newline separator.
- THE MAC HEALTH CHECK RAN EVERY 2 SECONDS while the panel was open, listing
  the heartbeat directory and hashing inbox.md each time. Throttled to 20
  seconds, far below the 5-minute grace.

Also added: a SOAK in `deploy.sh`. Every recorded stall began minutes AFTER a
verification passed (17:04 pass, 17:07 stall), so a point-in-time check is not
evidence that an install is safe. The script now waits `SOAK_SECONDS`
(default 300), writes a second probe, and re-proves both directions before it
prints success. It names the pattern explicitly when the soak fails.

Deliberately NOT done: the direct Mac to iPhone relay. Two stalls, both after
a reinstall, are not yet grounds for a second sync transport in an app whose
biggest reliability risk today was new code. See the reasoning recorded with
the decision.

### Sync monitoring, corrected (0.4.3, 2026-09-03 evening)

The 0.4.2 health work was itself a load on the transport it watched, and its
warning logic would not have fired during the very stall it was built for.
Both are fixed here. An independent review (Codex, read-only, same evening)
found five of the seven defects below; the churn regression was found by
correlating the Mac's `bird` upload counts against the deploy time.

- HEARTBEAT CHURN, a regression introduced by 0.4.2. Each device rewrote its
  heartbeat every 5 minutes unconditionally. The Mac app is resident all day,
  so an idle folder became a permanent iCloud writer: uploads went from about
  14 an hour before the deploy to 24 after, and 38 once the phone joined in.
  Now the Mac writes on launch, on a real inbox change, and at most hourly;
  iOS writes on launch, activation, capture, inbox change, and at most every
  2 minutes AND only while foregrounded. Roughly a twelfth of the traffic.
  Whether that churn contributed to the 17:07 to 19:20 phone-side iCloud
  stall is unproven, but monitoring must not tax what it measures.
- DISAGREEMENT TIMING. `peerLine` derived the duration of a digest mismatch
  from the peer's heartbeat age, so a peer publishing fresh heartbeats with
  stale bytes (exactly the evening stall) would have suppressed the warning
  forever. Replaced by `evaluatePeer`, which takes and returns a locally
  persisted `disagreementSince`. Two rules now: a live peer (checked in within
  15 min) holding different bytes for 5 min says "iCloud is not delivering";
  a peer silent for 2 hours says "last seen from X". A stale-but-quiet peer,
  such as a phone in a drawer, is neither, and stays silent.
- FALSE AGREEMENT. "Up to date with MacBook M4" required only that a peer
  heartbeat exist. It now requires one at most 2 minutes old whose digest
  matches ours; otherwise the wording is "Local copy checked just now", which
  is all a local read can honestly claim.
- SCOPED ACCESS LEAK. `openRoot` released the previous security scope only
  when the URL differed, so re-picking the same folder (the common case after
  a fault) leaked one access each time, toward the per-process cap that
  causes "lost access" until relaunch.
- REPAIRS REPORTED BUT NOT SAVED. A failed rewrite after a structural repair
  still reported the repair as done; it now reads "(not saved yet)".
- MAC FOLDER WATCHER missed the spool. A vnode source watches one directory,
  and `capture/drop.md` lives in a subdirectory, so out-of-app captures fired
  nothing. Both the root and `capture/` are watched now.
- MAIN-ACTOR STORE HANDED TO A DETACHED TASK during the download wait, which
  Swift 5 mode hides rather than rejects. The task builds its own store from
  the root URL. `readHeartbeats` also no longer materializes each file, which
  could block a UI caller 1.5 seconds per heartbeat.
- DEPLOY PROBE now appends through `NSFileCoordinator` via the new tracked
  `scripts/spool-append.js`, so it cannot race a drain, and writes in place so
  the Shortcuts bookmark on drop.md survives. Failure fails the verification
  instead of passing silently.
- The Mac menu bar gains a sync-health row, hidden while healthy, refreshed
  every 5 minutes whether or not the panel is open. The evening stall happened
  with the panel tucked away, where no surface could speak.

### Sync reliability (2026-09-03, docs/SYNC-RELIABILITY-BRIEF.md)

- ROOT CAUSE of the 2026-09-03 "sync is broken" morning: a stray backtick on the machine-written day header (`## 2026-09-03` followed by a backtick) made the strict header regex fail, so every entry under it was parsed as preamble. The Mac panel renders preamble as normal text; the iOS list renders days only. Identical bytes on both devices, a morning of "missing" notes. Not the bookmark, not the transport (unified log: every Mac write was uploaded by `bird` within 2 seconds).
- LedgeCore: `Inbox.parseReporting` reads leniently and reports repairs. A `## ` line carrying a real yyyy-MM-dd date is that day whatever follows; punctuation-only junk is dropped, junk with words is kept as the day's free text; duplicate sections for one day are merged newest first; days are re-sorted. `LedgeStore.loadInbox` rewrites the file in canonical form when anything was repaired and exposes `lastLoadRepairs`. `escapingStructure` uses the same lenient rule so writer and reader cannot drift. Six new tests; 50 total.
- iOS: `SyncFault` replaces the single "tap the folder icon" message with three causes and three fixes (grant dead: Re-pick; not downloaded: Download now with a 30 second real wait and percent; anything else: the underlying error and Try again). The folder grant is now proven by a zero-byte write in `.ledge/` at connect and on every explicit refresh; a bookmark that resolves but grants nothing can no longer reach `isConnected = true`. A successful read no longer clears the fault by itself: `.ubiquitousItemDownloadingStatus` must be `current`.
- iOS: a Refresh button beside the folder icon (and pull to refresh) runs `refreshNow()`: reconnect, probe, download with timeout, read, drain, flush, then always report an outcome ("Up to date, just now", "3 captures folded in", "Repaired: ...", or the fault).
- iOS: the heartbeat tick no longer turns a thrown read into an empty string; a failing read routes through `refresh()` and is classified. Text the parser cannot file under a day renders in an "Unfiled text" section instead of being invisible.
- Sync health (both apps): each device writes `.ledge/heartbeat-<device>.json` (device, ISO time, version, platform) on launch, on capture, and at most every five minutes while foregrounded. Every surface shows a muted "last seen from <device>: N hours ago" line only when another device's newest heartbeat is older than six hours. This measures the transport end to end; a connected folder was never the same thing as live sync.
- Mac: the `NSMetadataQuery` sync watcher was inert (`NSMetadataQueryUbiquitousDocumentsScope` needs an iCloud entitlement; the app is signed with none) and is replaced by a `DispatchSource` watch on the folder that logs each coalesced event. Background maintenance failures now surface in the panel header on the next summon; a failed re-read while the panel is open says so instead of staying "quiet by design"; repairs are named in the header.
- `scripts/deploy.sh`: every install is followed by verification against the Mac's copy of the iCloud folder. Mac: a macOS heartbeat newer than the launch carrying the built version. iPhone: a probe spool line appended before launch must be folded into inbox.md (Mac to phone), and an iOS heartbeat newer than the launch with the built version must arrive (phone to Mac). Anything short of both prints a numbered VERIFY SYNC block and exits 2; "Done" now means verified. Run it from a Terminal with Full Disk Access.
- Version 0.4.2 across VERSION, the Mac Info.plist and all four iOS targets, so the heartbeat assertion can tell a new build from the old one.

- Mac editor marks text as saved only after the write succeeds; a failed save now shows "not saved yet, will retry" instead of "captured" and keeps the text for the next commit (2026-09-02 fleet audit).
- iOS capture journal confirms own captures by minute stamp and device, so an entry edited on the Mac is no longer re-added as a duplicate, and a capture deleted elsewhere is not resurrected.
- iOS balances security-scoped folder access (one active scope per root) so repeated reconnects can no longer exhaust the per-process cap and show "lost access" until relaunch.
- Captured text that contains header-shaped or capture-marker-shaped lines is escaped with a zero-width space, so shared pages, Shortcut input and Watch relay text cannot forge attribution, dates, or day sections. Covered by a LedgeCore test.
- `Entry.id` is derived from stamp, device and text instead of a fresh UUID per parse, so the iOS list no longer rebuilds on every 2-second refresh.

# Ledge sync reliability: diagnosis brief and permanent-fix mandate

Written 2026-09-03 by a research session with read-only access to the repo, the
Mac, and the owner's durable session logs. Nothing in the repo was modified
except the creation of this file.

Read this whole file before you touch anything. It is self-contained: it assumes
you know nothing about this person, this app, or its history.

---

## 0. Your mandate

You are picking up a problem that has broken, been fixed, and broken again. The
owner's words: "it has to be flawless." Treat that as the acceptance bar.

1. **Diagnose from evidence, not from guessing.** Every claim in this file cites
   a file path, a command with its output, or a commit. Hold yourself to the same
   standard. Where this file infers rather than observes, it says so; do not
   promote an inference to a fact without re-testing it.
2. **Fix the root cause, not the symptom.** Re-picking a folder is a symptom fix.
   It has been performed at least twice and the problem returned both times.
3. **Add the monitoring that would have caught this on day one.** The single
   largest defect in this system is not any one bug. It is that nothing anywhere
   knows whether sync is alive. See section 5.
4. **Verify every claim by re-executing a check.** Do not write "sync is now
   working" unless you have watched a capture round-trip in both directions with
   timestamps.
5. **Then commit and push to GitHub.** The repo is public at
   github.com/ShashankKarpal/ledge.

### The governing SOP, which is mandatory

This repo is part of a personal fleet with a written standard operating
procedure. You must walk it before and after the work, not just read it:

- the `brand-surfaces-sop` skill (invoke it; it is the mandated gate for any
  change to this repo, including a rebuild or a device install)
- `~/Projects-with-Claude/shashankkarpal/design/brand/BRAND-SURFACES.md`
  (the ledge section starts at line 89; the two dated sync quirks are at lines
  102 to 120)
- the private operations extension named in the public SOP, file
  `design/brand/OPS-PRIVATE.md` in the private repository (the iCloud
  recovery move is at line 210)

Record any new quirk you discover back into the SOP. That is part of the job,
not an optional extra.

### The two boundary gates

Both are run only through the private operations repository's scripts. Do
not reimplement them. From the fleet root:

    bash <private-ops-repo>/scripts/run-boundary-gates.sh --pre-push
    bash <private-ops-repo>/scripts/audit-postpush.sh

The first runs before you push (it also does the distributor check, the SOP
comparison, and the derived fleet clean sweep). The second is read-only and runs
after the push round (remote parity, visibility allowlist, identifier sweep).
Both are documented at OPS-PRIVATE.md lines 114 to 124. Both files exist and are
executable; verified 2026-09-03.

### Git in a sandboxed Cowork session

If you are running inside a sandboxed Cowork session, **host git must run through
`osascript`, never through the sandbox shell.** Sandbox subagents that ran even
read-only git commands through the mount left stale `.git/index.lock` files in
four repos, after which `git add` on the host failed silently and four repos
looked unchanged at commit time (OPS-PRIVATE.md lines 320 to 327). Before any
host commit, sweep for `*/.git/index.lock` and confirm `pgrep -x git` returns
nothing.

Practical note for this environment: `osascript` chokes on complex quoting. The
reliable pattern is to base64 the script and decode it on the host:

    do shell script "echo <BASE64> | base64 --decode > /tmp/x.sh; bash /tmp/x.sh 2>&1"

---

## 1. Where things stand right now, 2026-09-03

Observed facts, each with the command that produced it.

| Fact | Evidence |
| --- | --- |
| iPhone and Watch were reinstalled this morning at 07:58 to 07:59 | `/tmp/ledge-devices.json` mtime 07:58, `/tmp/ledge-install.log` mtime 07:59, log tail shows `App installed: bundleID: com.shashankkarpal.ledge.watchkitapp` |
| The iOS build produced no errors | `/tmp/ledge-iosbuild.log` is 0 bytes (xcodebuild ran with `-quiet`) |
| Mac app was rebuilt and installed the previous evening | `/Applications/Ledge.app` mtime 2026-09-02 20:47; `/tmp/ledge-macbuild.log` mtime 2026-09-02 20:47 |
| The Mac app is running now | `pgrep -lf Ledge` returns pid 56641 |
| The Mac panel was summoned today | `defaults read com.shashankkarpal.ledge.mac` shows `ledge.morningShownDay = 2026-09-03` |
| Repo is clean and pushed | `git status --porcelain` empty; HEAD = origin/main = `2217305` (2026-09-03 08:54) |
| A Mac capture is not appearing on the iPhone | reported by the owner |
| Re-picking the folder on the iPhone did **not** fix it | reported by the owner |
| macOS 26.6.2, build 25G83, up 2 days 17 hours (booted approximately 2026-08-31 17:00) | `sw_vers`, `uptime` |
| `bird`, `fileproviderd`, `cloudd` have not restarted since that boot | `ps -Ao pid,etime,comm` shows etime `02-17:00:55` for all three |
| No macOS update landed between the last sync fix and today | `/Library/Receipts/InstallHistory.plist`: only XProtect data 5356/5357/5358 and Logitech webcam drivers (2026-09-03 01:15) |
| The iCloud folder cannot be inspected by automation | `ls ~/Library/Mobile Documents/com~apple~CloudDocs/Ledge` returns `Operation not permitted` |
| `brctl` cannot be used by automation either | `brctl status` returns `Error Domain=BRCloudDocsErrorDomain Code=141 "Access denied"` |

**What the folder re-pick result tells you.** Re-picking rebuilds the
security-scoped bookmark, which is failure mode A below. It did not help.
That points at the transport (failure mode C), or at a stale read that the app
cannot distinguish from a fresh one (failure mode J, which is new and unfixed).

**Access constraint you must respect.** The iCloud folder and `brctl` are
TCC-denied to automation. You cannot inspect the live data. Do not fake it, and
do not report on files you have not read. Section 6 marks exactly which steps
Shanky must run in his own Terminal.

---

## 2. The architecture, in plain language

### The data

There is no server, no account, no database. The folder is the database. Default
root on the Mac is `~/Library/Mobile Documents/com~apple~CloudDocs/Ledge`
(`core/Sources/LedgeCore/Store.swift` lines 55 to 68).

Inside it (`Store.swift` lines 40 to 51):

- `inbox.md` : the one file that matters. Days newest first, entries newest
  first, `## yyyy-MM-dd` day headers and `### HH:mm · Device` entry headers.
- `capture/drop.md` : the **spool**. A flat append-only list of
  `[[yyyy-MM-dd HH:mm · Device · #id]] text` lines, written by anything that
  cannot safely edit `inbox.md`, drained into `inbox.md` by the apps.
- `notes/`, `attic/`, `assets/` : long-form notes, aged-out days, attachments.
- `.ledge/settings.json` : panel width, aging days, hotkey, theme.
- `.ledge/seen-capture-ids.txt` : the last 500 capture delivery ids that have
  already been folded, so the Watch relay can deliver twice safely.

### Who writes what, in what order

**Mac capture.** The user presses Option+Space, the panel opens, they type. On
dismiss, `PanelContent.commit()` parses the editor text back into an `Inbox` and
calls `LedgeStore.saveInbox`, which does the whole check-merge-write inside one
`NSFileCoordinator` coordinated write (`Store.swift` lines 181 to 233). iCloud
then uploads `inbox.md` at its own discretion. Nothing in the app can force that
upload.

**Mac out-of-panel capture.** The mini popover and the drag-drop strip go through
`AppDelegate.quickCapture`, which loads, drains, prepends, saves.

**iPhone in-app capture.** `AppModel.capture` writes straight into `inbox.md` via
`saveInbox`, then records the capture in a local journal so an iCloud race cannot
lose it (`apps/ios/Sources/Model/AppModel.swift` lines 174 to 193 and 284 to 311).

**iPhone out-of-app capture** (widget, Control Center, Siri App Intent, share
sheet): `SpoolWriter.append` writes one spool line into `capture/drop.md`
(`apps/ios/Sources/Model/SpoolWriter.swift` lines 38 to 61). It never touches
`inbox.md`.

**Watch capture.** The Watch cannot reach the iCloud folder at all; this is a
design constraint, recorded in `docs/spec.md` line 189. `WatchSessionManager.send`
attaches a UUID delivery id and sends over WatchConnectivity: `sendMessage` when
the phone is reachable, `transferUserInfo` otherwise, and it re-queues any
transfer whose `didFinish` reports an error
(`apps/ios/WatchSources/WatchSessionManager.swift` lines 28 to 86). On the phone,
`SessionManager.handle` funnels it onto a serial queue and calls
`SpoolWriter.append` with `device: "Apple Watch"` and that id
(`apps/ios/Sources/SessionManager.swift` lines 27 to 38). So **the Watch reaches
the data only through the phone**, and Watch capture keeps working even when
iCloud is completely dead. That is why "the Watch still works" is not evidence
that sync is fine.

**Draining.** `LedgeStore.drainSpool` reads `drop.md`, drops any capture whose id
is already in `seen-capture-ids.txt`, folds the rest into the in-memory inbox,
truncates exactly the bytes it consumed, and records the ids
(`Store.swift` lines 243 to 300). Drains happen: on iOS at scene activation,
on pull to refresh, and on every 2-second foreground heartbeat tick; on the Mac
at launch, on every panel summon, on the panel's own 2-second timer, and on a
300-second background timer that only runs while the panel is hidden
(`apps/mac/Sources/AppDelegate.swift` lines 60 to 68).

### The security-scoped bookmark, and why iOS needs one

The Mac app opens the iCloud folder by absolute path; it has no sandbox
restriction to satisfy. The iOS app cannot do that. An iOS app is confined to its
own container, and the only way it can touch a path outside that container is if
the user hands it over through the system document picker. That grant is handed
back as a URL carrying a sandbox extension, and the only way to keep it across
launches is to serialise it as **bookmark data**.

In this app:

- `AppModel.connectFolder` calls `url.bookmarkData(...)` and stores the blob in
  `UserDefaults` under the key `ledge.folderBookmark`
  (`AppModel.swift` lines 42 to 58; the key is `SpoolWriter.bookmarkKey`,
  `SpoolWriter.swift` line 12).
- `AppModel.restore` resolves it, then calls
  `url.startAccessingSecurityScopedResource()` and treats a `false` return as
  disconnected (`AppModel.swift` lines 61 to 94).
- `openRoot` stops the previous scope before starting a new one, because iOS caps
  concurrent scoped accesses per process and the old code leaked one per
  reconnect (`AppModel.swift` lines 96 to 120; fixed in commit `3412197`).

**The fragile part:** the bookmark blob survives a reinstall (it lives in the
container, which `devicectl device install app` preserves), so it still
*resolves* to a URL, but the sandbox extension that makes it usable is issued per
install. After a reinstall the app can therefore hold a bookmark that resolves
and yet grants nothing. That is exactly the quirk recorded in BRAND-SURFACES.md
lines 102 to 112 on 2026-08-19.

### Where the pending queues live

- **iPhone/iPad:** `Documents/pending-captures.md` inside the app container
  (`SpoolWriter.pendingURL`, lines 16 to 19). Written whenever the folder cannot
  be reached. Flushed by `AppModel.flushPending`, which is called from
  `openRoot`, `becameActive`, and every heartbeat tick that sees a non-empty
  queue (`AppModel.swift` lines 205 to 220 and 251).
- **Apple Watch:** the OS holds it, as `WCSession.outstandingUserInfoTransfers`.
  The watch UI shows the count. Delivery is the OS's job.
- **Mac:** there is none. The Mac writes directly, and a failed write surfaces as
  "not saved yet, will retry" in the panel header (`PanelContent.swift` lines 203
  to 227).

### What actually moves bytes between devices

iCloud Drive, and nothing else. Neither app has a CloudKit container, a ubiquity
container, or push. `docs/spec.md` line 228 states this explicitly:
"no CloudKit, no ubiquity container, no push, anywhere."

Neither app registers an `NSFilePresenter` and neither uses FSEvents; verified by
grepping the whole tree for `NSFilePresenter|FSEvent|presentedItem|DispatchSource`,
which returns matches only for `NSMetadataQuery` in `AppDelegate.swift`. Both apps
therefore **poll**. Downloads are requested only when an app is open and reading.

---

## 3. Every known failure mode

Each entry gives the symptom as experienced, the underlying cause, how to tell it
apart from the others, and the fix. A to I are historical and fixed. J to L are
live and unfixed; J is the most likely explanation for today.

### A. Security-scoped bookmark invalidated by a reinstall (fixed, recurs by design)

- **Symptom:** Mac notes stop appearing on the iPhone. Watch capture still works.
  iPhone captures do not reach the Mac either. Nothing is lost: captures land in
  `pending-captures.md`.
- **Cause:** `devicectl` reinstall re-signs the app; the persisted bookmark still
  resolves but the sandbox extension is not re-issued, so
  `startAccessingSecurityScopedResource()` returns false.
- **Tell it apart:** the folder icon in the top left of the iOS app renders as
  `folder.badge.questionmark` instead of `folder`
  (`apps/ios/Sources/Views/RootView.swift` line 44), and the banner reads
  "Ledge lost access to your folder."
- **Fix:** tap the folder icon and re-pick iCloud Drive > Ledge.
- **Evidence:** BRAND-SURFACES.md lines 102 to 108; session log
  `_claude-chats/kk1/2026-08-19_0921_kk1-cowork_ledge-sync-incident-sop.md`
  lines 27 to 31.

### B. App state hid failure mode A (fixed 2026-08-19)

- **Symptom:** sync was dead for a full morning while the app looked healthy.
- **Cause:** two bugs. `startAccessingSecurityScopedResource()`s return value was
  ignored, and `refresh()` never set `isConnected = false` on a read failure. The
  re-pick button was only shown when `isConnected` was false, so the recovery
  path was invisible precisely when it was needed.
- **Fix:** commit `63e2439` (2026-08-19 08:58). The button is now always visible,
  and failed scope access and failed reads both mark the app disconnected.
- **Do not regress the always-visible button.** BRAND-SURFACES.md line 112 says
  so in as many words.

### C. iCloud Drive transport wedged (fixed operationally only)

- **Symptom:** the app is healthy and connected, but the iPhone holds `inbox.md`
  as a greyed dataless placeholder in the Files app, and iPhone writes never
  reach the Mac.
- **Cause:** the sync daemons themselves. Not an app bug.
- **Tell it apart:** the folder icon shows a plain `folder` (connected), and
  `inbox.md` is grey with a cloud-arrow badge in Files on the iPhone.
- **Fix:** `killall bird fileproviderd` on the Mac, force-download `inbox.md`
  from the iPhone Files app, pull to refresh in Ledge, then verify a fresh
  capture round-trips **both** ways.
- **Evidence:** BRAND-SURFACES.md lines 113 to 120; OPS-PRIVATE.md line 210.

### D. Capture stranded in the spool for days (fixed 2026-08-17)

- **Symptom:** a thought is captured, is nowhere in the inbox, and reappears days
  later.
- **Cause:** the Mac drained the spool only at launch and on panel summon. One
  capture sat in `drop.md` from 2026-08-16 13:47 while the panel had last been
  summoned on 2026-08-07 (`docs/STATUS-2026-08-17.md` line 20). An earlier one
  sat eleven days (`Spool.swift` lines 102 to 104).
- **Fix:** commit `21cd69c` added the 300-second background drain timer and the
  muted "N captures waiting" line on both surfaces.
- **Tell it apart:** the waiting line is visible. If you see
  "3 captures waiting since 2026-08-30 09:14", this is the mode you are in, and
  it is a drain problem, not a transport problem.

### E. Shortcuts file bookmark orphaned by the spool drain (fixed 2026-07-27)

- **Symptom:** the Shortcuts "Capture to Ledge" recipe silently stopped
  appending, on every run.
- **Cause:** the drain replaced `drop.md` atomically, which changes the file's
  identity and orphans the out-of-process bookmark the Shortcuts action holds.
- **Fix:** commit `234ff67` introduced `LedgeStore.writeStringInPlace`, which
  truncates and rewrites in place instead (`Store.swift` lines 545 to 578). Note
  the fix could not heal an already-broken bookmark; the recipe had to be
  re-pointed by hand, and no artifact records that ever happening
  (`docs/STATUS-2026-08-17.md` line 38).

### F. Null-byte corruption from racing coordinated writes (fixed)

- **Symptom:** duplicate entries plus garbage bytes inside entry bodies,
  2026-08-17.
- **Cause:** the old `saveInbox` did the stamp check, the merge, and the write as
  separate steps, leaving a window for another coordinated writer to land bytes
  in between.
- **Fix:** the check, merge, and write now happen inside one coordinated write
  (`Store.swift` lines 183 to 215), plus `strippingNulls` and
  `collapseExactDuplicates` on load.

### G. Watch capture dropped when a transfer errored (fixed 2026-08-17)

- **Cause:** a `didFinish` carrying an error was treated as delivered.
- **Fix:** `WatchSessionManager.swift` lines 72 to 86 re-queue on error; the
  delivery id makes the resulting duplicate harmless.

### H. Scoped-access cap exhausted by repeated reconnects (fixed 2026-09-02)

- **Symptom:** "lost access" that persists until the app is force-quit and
  relaunched.
- **Cause:** every `openRoot` started a new scoped access and never stopped the
  old one.
- **Fix:** commit `3412197`, `AppModel.openRoot` lines 102 to 107.

### I. Mac editor marked text saved after a failed write (fixed 2026-09-02)

- **Symptom:** typed text vanished on the next summon.
- **Cause:** `lastSetEditorText` moved unconditionally, so a failed save looked
  like a success and the next reload from disk discarded the text.
- **Fix:** commit `3412197`, `PanelContent.swift` lines 203 to 227.

### J. A stale read is indistinguishable from a fresh one (LIVE, unfixed)

- **Symptom:** exactly today's. The app is connected, no banner, no waiting line,
  and the Mac's newest note simply is not there. Re-picking the folder changes
  nothing because the bookmark was never the problem.
- **Cause:** nothing in the codebase ever asks whether the bytes it just read are
  current. `LedgeStore.materialize` (`Store.swift` lines 432 to 452) takes the
  branch for a file that exists, calls `startDownloadingUbiquitousItem`, waits at
  most 1.5 seconds in `awaitFreshness`, and then **returns void regardless of the
  downloading status**. `readString` then reads whatever local copy exists. If
  that copy is a week old, the read succeeds, `refresh()` sets
  `isConnected = true` and `notice = nil` (`AppModel.swift` lines 143 to 145),
  and the UI reports perfect health while showing stale data.
- **Tell it apart:** compare the newest entry timestamp shown on the phone
  against the newest entry in `inbox.md` on the Mac. If the Mac's file has the
  entry and the phone does not, and the phone shows no error, you are here.
- **Fix:** not yet written. See section 5, items M3, M4 and M6.

### K. Every read failure blames the bookmark (LIVE, unfixed)

- **Symptom:** the app tells him to re-pick the folder when re-picking cannot
  possibly help, which is what happened today.
- **Cause:** `AppModel.refresh`s single catch block
  (`AppModel.swift` lines 146 to 152) emits one message,
  "Ledge could not read your folder. Tap the folder icon and pick it again.",
  for every possible failure: dead sandbox extension, undownloaded file, iCloud
  outage, disk error, parse error.
- **Fix:** see section 5, item M3.

### M. A damaged header demotes everything under it to preamble (FOUND 2026-09-03, the actual cause of that day; fixed)

- **Symptom:** exactly today's. Connected, no banner, no waiting line, Files
  app shows `inbox.md` downloaded with the same mtime and size as the Mac
  (09:36, 3 KB versus 09:36:19, 3309 bytes), and the Mac's newest notes are
  still not on the phone.
- **Cause:** line 1 of the live file read `## 2026-09-03` followed by a
  backtick. `LedgeFormat.isDayHeader` requires `^## \d{4}-\d{2}-\d{2}\s*$`,
  so the line was not a header; `Inbox.parse` then filed both Mac entries
  under it into `preamble`, which iOS never rendered and the Mac panel (raw
  text) rendered as normal. The phone's own capture later created a second,
  clean `## 2026-09-03` section below the damaged one, exactly as predicted
  before it was observed. How the backtick got there is inference (the key
  sits beside Esc, which dismisses the panel, and the header line sits one
  line above the caret); the byte is fact.
- **Tell it apart:** `head -3 inbox.md` on the Mac. If a day header is not
  exactly `## yyyy-MM-dd`, this is the mode. Since 0.4.2 both apps repair it
  on read and say so ("repaired the day header for 2026-09-03").
- **Fix (0.4.2):** `Inbox.parseReporting` accepts a dated `## ` line with
  trailing junk as that day, merges duplicate same-day sections, and reports
  every repair; `loadInbox` rewrites the file in canonical form. iOS renders
  any remaining preamble under "Unfiled text". See CHANGELOG.
- **Evidence:** owner's Terminal paste 2026-09-03 12:2x (`stat`, `head -20`),
  iPhone screenshots of Ledge and of Files > iCloud Drive > Ledge at 12:18
  and 12:19, unified log correlation of Ledge coordinated writes with `bird`
  "uploading 1 documents" (09:35:29.067 to 09:35:29.335, and so on), and the
  `grep -n 'sync probe 0903b'` match at line 10 after `bird` "finished
  downloading 1 documents" at 12:28:59.
- **What this changes about section 4:** the reinstall correlation still holds
  for 2026-08-19 (failure mode A). For 2026-09-03 the reinstall was the reason
  the owner ran a probe capture at all; the probe itself carried the damage.
  Reinstalls remain a trigger for A and for the transport; they were not the
  cause of M.

### L. The Mac sync watcher watches nothing (VERIFIED 2026-09-03 by entitlements; replaced)

Update 2026-09-03: `codesign -d --entitlements` on `/Applications/Ledge.app`
prints no entitlements and `TeamIdentifier=not set`; the ubiquitous scopes
require an iCloud entitlement, so the query could gather nothing. Replaced
in 0.4.2 by a `DispatchSource` vnode watch on the folder that logs
`Ledge: folder changed (event N)`; `log stream --process Ledge` now shows it.
Original text follows.

#### L, as written before verification

- **Claim:** `AppDelegate.startSyncWatcher` (lines 74 to 93) builds an
  `NSMetadataQuery` with `searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]`.
  That scope covers the calling application's own ubiquity container.
  `docs/spec.md` line 228 states this app deliberately has no ubiquity container.
- **Inference:** the query returns zero results, `syncWatcherFired` never calls
  `startDownloadingUbiquitousItem` on anything, and the comment at lines 70 to 73
  claiming it "keeps the Mac's local copies fresh" describes behaviour that does
  not happen. If true, the Mac has no push-driven download path at all; it only
  ever pulls when something reads.
- **This is labelled inference because it has not been observed at runtime.**
  Verify it before acting on it: add a temporary `NSLog` of `query.resultCount`
  inside `syncWatcherFired`, rebuild, and read it with
  `log stream --predicate 'process == "Ledge"'`.

---

## 4. Why it keeps coming back

### The timeline, from git and the session logs

| Date | Event | Source |
| --- | --- | --- |
| 2026-07-24 | v0.2 ships; first install on all devices | `799ef2c`, `71e6430` |
| 2026-07-27 | Shortcuts bookmark orphaning fixed; `deploy.sh` created; iOS heartbeat added | `234ff67`, `2df4c26`, `a707685` |
| 2026-08-01 | v0.4.0 | `9ebd0b0` |
| 2026-08-16 13:47 | a capture lands in `drop.md` and is never folded | `docs/STATUS-2026-08-17.md` line 20 |
| 2026-08-17 | heavy reinstall day: Siri fix, Watch install, on-device verification, capture-trust work | `4a26a6e`, `fc325d2`, `4471c7b`, `21cd69c`, `146bddb`, `4407c23`, and five kk2 session logs |
| 2026-08-19 08:58 | **sync reported broken after the reinstalls**; three stacked layers diagnosed and fixed; round trip verified at 08:39 and 09:13 | `63e2439`; `_claude-chats/kk1/2026-08-19_0921_kk1-cowork_ledge-sync-incident-sop.md` lines 16, 27 to 34 |
| 2026-08-19 | both quirks written into BRAND-SURFACES.md | lines 102 to 120 |
| 2026-08-31 approx 17:00 | Mac last booted; `bird`/`fileproviderd` start | `uptime`, `ps -Ao etime` |
| 2026-09-02 20:47 | Mac app rebuilt and installed | `/Applications/Ledge.app` mtime |
| 2026-09-02 21:02 | fleet-audit commit: iOS journal, scoped access, Mac save-on-success | `3412197` |
| 2026-09-03 07:58 to 07:59 | **iPhone and Watch reinstalled via `deploy.sh ios`** | `/tmp/ledge-devices.json`, `/tmp/ledge-install.log` |
| 2026-09-03 morning | **sync reported broken**; folder re-pick does not fix it | owner report |

### Testing the hypothesis that reinstalls are the trigger

**Supported.** Both dated sync breakages in the whole record follow a device
reinstall within hours. 2026-08-19 follows the 2026-08-17 reinstall day and the
session log names the reinstalls as the cause of layer 1. 2026-09-03 follows a
07:58 reinstall the same morning. There is no recorded sync breakage that is not
preceded by a reinstall.

**Not supported: a ten-day clock.** The felt interval is real but it is the
interval between deploys, not a timer. Deploy dates in the record: 07-24, 07-27,
08-01, 08-17, 08-19, 09-03. The gap from 08-17 to 08-19 is two days; the gap from
08-19 to 09-03 is fifteen. Sync survives as long as nobody reinstalls.

**Ruled out: an OS update.** `/Library/Receipts/InstallHistory.plist` shows
nothing between 2026-08-19 and 2026-09-03 except XProtect data updates
(5356, 5357, 5358) and Logitech webcam drivers at 2026-09-03 01:15. macOS is
26.6.2 build 25G83 and did not change.

**Ruled out: the Mac hostname rename.** It was planned in detail on 2026-09-01
but has not started; the M4 is still named `helios`
(`_claude-chats/kk1/2026-09-01_1837_kk1-cowork_m4-rename-runbook-handoff.md`
lines 31 and 54). Only the M1 was renamed, and the M1 does not run Ledge.

**Ruled out: free-provisioning profile expiry.** That would give a genuine
seven-day cycle, but this repo signs with the paid Apple Developer Program team
(`cc9fd1b`, `9857270`), so development profiles last a year.

**Open, and today's most likely proximate cause:** the transport, layer 3 of the
2026-08-19 incident, recurring. Note that on 2026-08-19 the transport was wedged
*at the same time* as the bookmark, immediately after reinstalls. A plausible
mechanism is that killing and replacing the app mid-sync leaves the file provider
in a bad state for that folder. **This is inference. It has not been proven, and
proving it needs instrumentation that does not exist yet.**

### What is genuinely fragile

1. **The iOS folder grant cannot survive a reinstall, and there is no API that
   makes it.** iOS re-issues sandbox extensions per install. The persisted
   bookmark outlives the grant, which is the worst of both worlds: it resolves,
   so the app believes it has a folder.
2. **iCloud Drive is a transport nobody can force or inspect.**
   `startDownloadingUbiquitousItem` is a request, not a command. There is no
   upload equivalent at all. `brctl status` is denied even to automation on this
   machine (verified today, error 141 Access denied).
3. **Both apps poll, and only while open.** No `NSFilePresenter`, no FSEvents, no
   ubiquity container, and per failure mode L the Mac's one metadata watcher is
   probably inert. A closed iPhone app is a device that has stopped syncing.
4. **The app fails silently by construction.** See section 5. The project's own
   red-team document already named this: "Calm is a UI stance, not an
   observability policy" (`docs/ROADMAP-REDTEAM-2026-08-17.md` line 50).
5. **Nothing anywhere monitors whether sync is alive.** The only observability
   ever shipped is the waiting-capture line, and it measures the spool, not the
   transport. A wedged transport produces an empty spool and a clean UI.
6. **`scripts/deploy.sh` ends at "installed" and never checks that the thing it
   just replaced still works.** It has exit 0 with sync dead at least twice.

---

## 5. Why it fails silently: the exact code paths

Named function by named function. These are the places where a failure produces
no visible signal.

1. **`AppModel.heartbeatTick`** (`AppModel.swift` lines 246 to 260). Both reads
   are written as `((try? store.readString(...)) ?? nil) ?? ""`. A thrown error
   becomes the empty string. On the first failing tick, `raw` is `""` and
   `lastSeenDiskRaw` is also `""` (its initial value, line 228), so the guard on
   line 254 returns early: no refresh, no notice, `isConnected` untouched. While
   the transport is wedged the heartbeat runs every two seconds and does nothing,
   forever, without saying so.
   **Missing check:** distinguish "read threw" from "read returned empty".

2. **`LedgeStore.materialize`** (`Store.swift` lines 432 to 452). For a file that
   exists it nudges the download, calls `awaitFreshness` with a 1.5 second
   timeout, and returns void. `awaitFreshness` (lines 458 to 471) polls
   `.ubiquitousItemDownloadingStatusKey` but discards the result when it times
   out. Its own comment calls it "best effort, never throws".
   **Missing check:** nothing after this point ever looks at the downloading
   status again, so `.notDownloaded` / `.downloaded` versus `.current` never
   reaches the UI.

3. **`LedgeStore.readString`** (`Store.swift` lines 496 to 519). Returns whatever
   local bytes exist. There is no freshness assertion, no comparison against a
   remote version, no age check.
   **Missing check:** a "this copy is older than the newest known version" test.
   This is the mechanical root of failure mode J.

4. **`AppModel.refresh`** (`AppModel.swift` lines 133 to 154). On success it sets
   `isConnected = true` and `notice = nil`, which is a positive health claim made
   purely on the basis that a read did not throw. On failure it emits one generic
   message naming the folder icon, for every possible cause.
   **Missing check:** a cause discriminator before choosing the message.

5. **`SpoolWriter.append`** (`SpoolWriter.swift` lines 38 to 61). The catch falls
   back to `appendToPending` with no notice at all. The capture is safe, but the
   user learns nothing until the waiting line appears, and the waiting line only
   renders while the app is open.

6. **`SpoolWriter.appendToPending`** (line 70) writes with `try?`. If that write
   fails, the capture is gone and nothing anywhere records it. This is the last
   line of defence and it is unchecked.

7. **`AppDelegate.maintain`** (`apps/mac/Sources/AppDelegate.swift` lines 149 to
   159). The catch does `NSLog` only. The Mac app is `LSUIElement = true`; it has
   no window and nobody reads its log.

8. **`AppDelegate.applicationDidFinishLaunching`** (lines 24 to 28). A failed
   `bootstrap()` is logged and then execution continues as if the store were
   fine.

9. **`PanelContent.refreshFromDiskIfClean`** (`PanelContent.swift` lines 284 to
   286). The catch body is a comment: "Quiet by design; the next summon retries
   with full handling."

10. **`AppDelegate.syncWatcherFired`** (lines 95 to 113) iterates
    `query.results`. If that is always empty (failure mode L), the loop is a
    no-op and there is no log line, no counter, nothing.

11. **`AppModel.flushPending`** (lines 205 to 220). The catch sets a notice, but
    the notice is cleared unconditionally by the next successful `refresh()`
    (line 145), which runs on the very next heartbeat tick two seconds later.
    Any transient failure message is effectively invisible.

The net effect: **he finds out sync is dead by noticing a note is missing,
sometimes days later.** That is the actual bug. Everything else is detail.

---

## 6. What "flawless" would actually require

Design only. Do not implement any of this before the runbook in section 7 has
established the current root cause and proven a round trip.

### Must-have

**M1. Detect a dead grant immediately and loudly at launch.**
Be honest with him first: there is no iOS API that makes a security-scoped
bookmark survive a reinstall or a re-sign. The grant is per install. So the goal
is not survival, it is instant detection plus one-tap recovery.
Replace the current implicit test with a real probe in `AppModel.restore`:
after `startAccessingSecurityScopedResource()` returns true, write and delete a
zero-byte file under `.ledge/` (or read `inbox.md`s attributes) and treat any
failure as disconnected. A resolvable bookmark that grants nothing must never
reach `isConnected = true`. Surface it as a blocking card with a Re-pick button,
not an amber line that competes with the calm rules. The always-visible folder
button stays (BRAND-SURFACES.md line 112).

**M2. An explicit Refresh control next to the folder icon.**
He has asked for this by name and it is small. `AppModel.refresh()` already
exists (line 133) and `.refreshable` is already wired
(`InboxView.swift` lines 64 to 68). Add a `ToolbarItem` beside the folder button
that calls a new `refreshNow()` which: reconnects if needed, reads, drains,
flushes, and then **reports an outcome** ("up to date, 2 seconds ago",
"3 folded in", "could not download your inbox"). Do not reuse `becameActive()`
directly: when `isConnected` is false it early-returns into `restore()`
(lines 126 to 129), and if the scope fails there it stops with a notice and never
attempts a read. The button must always produce a visible result, including
"nothing changed", so pressing it is informative rather than an act of faith.

**M3. Three causes, three messages.**
Before choosing the notice text, discriminate:
(a) scope probe failed, so the grant is dead: say so, offer Re-pick;
(b) `.ubiquitousItemDownloadingStatusKey` is not `.current`, so the file has not
downloaded: say so, offer Download now (see M6);
(c) anything else: say so plainly and include the underlying error.
This alone would have saved today, because the app would have told him not to
bother re-picking.

**M4. A real health indicator: the heartbeat file.**
The app currently reports whether a folder is connected. It must report whether
sync is alive. Design:

- Each device writes `.ledge/heartbeat-<device-slug>.json` containing an ISO
  timestamp, the device label, and the app version. Write on launch, on capture,
  and at most every five minutes while foregrounded. Keep it out of `inbox.md`
  so it can never cause a conflict on the file that matters.
- Every surface reads all heartbeat files and shows, under the capture bar,
  a muted line only when the newest heartbeat from another device is older than a
  threshold: "last seen from MacBook M4: 4 hours ago". Silent when healthy, which
  respects the no-badges rule the same way the waiting line does.
- This measures the transport end to end. A wedged iCloud shows an old stamp; a
  dead bookmark shows a read failure; a healthy system shows nothing. It is the
  one addition that turns a silent failure into a visible one.
- Cost: a handful of tiny files and a small amount of sync churn. Accept it.
  Threshold should be generous (start at 6 hours) so a phone left in a drawer
  does not nag.

**M5. Post-deploy verification inside `scripts/deploy.sh`.**
A reinstall must not be able to leave sync broken silently. The script currently
prints "Done" after `devicectl device install app` succeeds
(`scripts/deploy.sh` lines 159 to 177). Add a verification stage:

- Write a probe capture on the Mac with a unique token, through
  `LedgeStore` semantics (append one spool line to `capture/drop.md`, which is
  the safe file to touch from a script).
- Launch the app on the phone so it registers and reads:
  `xcrun devicectl device process launch --device "$IPHONE_ID" com.shashankkarpal.ledge`.
- Then either assert automatically or block on the human. Worth testing whether
  `xcrun devicectl device info files --device "$IPHONE_ID" --domain-type
  appDataContainer --domain-identifier com.shashankkarpal.ledge` can list the
  container; if it can, the script can assert that `pending-captures.md` is
  absent or empty, which is a genuine post-install health assertion. If it
  cannot, the script must still refuse to print a clean "Done" and instead print
  a numbered VERIFY SYNC block that names the probe token and requires the
  operator to confirm it appeared on the phone.
- Rank: the blocking checklist is must-have; the automated assertion is
  nice-to-have and depends on what `devicectl` actually allows.

**M6. Detect the dataless state in-app and offer one-tap force download.**
Read `.ubiquitousItemDownloadingStatusKey` on `inbox.md`. If it is not
`.current`, show "Your inbox has not finished downloading" with a Download
button that calls `startDownloadingUbiquitousItem` and polls with a real timeout
(30 seconds), showing `.ubiquitousItemPercentDownloadedKey` while it waits.
This removes the trip to the Files app entirely.
Honest limit: if the wedge is on the Mac side, nothing the phone does will fix
it. The phone can only report accurately, which is still a large improvement
over reporting nothing.

### Nice-to-have

**N1. `scripts/sync-doctor.sh`.** One script Shanky runs in his own Terminal
(where TCC permits it) that prints on one screen: `inbox.md` size and mtime, the
newest entry timestamp, the contents of `capture/drop.md`, every heartbeat stamp,
any `*.icloud` placeholders in the tree, and the uptimes of `bird`,
`fileproviderd` and `cloudd`. This is the artifact that would have made today a
two-minute diagnosis.

**N2. Fix or remove the Mac sync watcher.** Verify failure mode L first with a
logged `resultCount`. If it is inert, either scope the query correctly or replace
it with a `DispatchSource` file watcher on the folder. Do not leave a comment
claiming behaviour the code does not have.

**N3. Register an `NSFilePresenter` on both platforms** so each app is told when
the other writes, instead of polling. `docs/spec.md` line 259 already claims iOS
does this; it does not. Either implement it or correct the spec.

**N4. Background refresh on iOS** via `BGAppRefreshTask`, so the phone touches the
folder occasionally without being opened. Honest limit: iOS schedules these at
its own discretion and may never run them. It can improve latency; it must never
be the health mechanism.

### Later

**L1.** A Mac menu bar state that goes amber when the newest heartbeat from any
other device is older than the threshold. The menu bar item already exists
(`StatusItemController`).

**L2.** Surface `scripts/seven-day-gate.sh` output inside the app, so capture
health and sync health live on one surface.

**L3.** An optional second transport (a git remote, or a Syncthing folder) for
the day iCloud is the problem and cannot be fixed. This is a large change and
should not be considered until M1 to M6 have been in service long enough to
prove they are not enough.

### What iOS genuinely will not allow

- Persisting a folder grant across a reinstall or a signing-identity change.
  Detect and re-grant is the ceiling.
- Forcing an iCloud Drive upload. There is no API. Downloads can be requested;
  uploads cannot be requested at all.
- Keeping a folder fresh while the app is closed, absent a ubiquity container
  (which this design deliberately does not have, `docs/spec.md` line 228).
- Reading `bird` or `fileproviderd` state from inside the app.
- Reading the iCloud folder from automation on the Mac; TCC denies it, verified
  today.

---

## 7. Diagnostic runbook, in order, from the current broken state

Run these in sequence. Do not skip ahead. Steps marked **[SHANKY]** need a human:
his own Terminal for the TCC-protected folder, or hands on an unlocked device.
Steps marked **[MODEL]** you can do yourself.

**Step 1 [MODEL].** Re-read the repo state and confirm nothing has changed since
this brief was written:

    cd ~/Projects-with-Claude/ledge && git status --porcelain && git log -1 --oneline

Expected: empty status, HEAD `2217305`. If HEAD differs, someone has committed
since; read the diff before proceeding.

**Step 2 [SHANKY], his own Terminal.** Prove the folder exists and what is in it:

    ls -la ~/Library/Mobile\ Documents/com~apple~CloudDocs/Ledge

Expected: `inbox.md`, `capture/`, `notes/`, `attic/`, `assets/`, `.ledge/`.
If you get `Operation not permitted`, the Terminal needs Full Disk Access
(System Settings > Privacy and Security > Full Disk Access). If `inbox.md` is
missing entirely, stop and say so; that is a different and much worse problem.

**Step 3 [SHANKY].** Freshness of the Mac's own copy:

    cd ~/Library/Mobile\ Documents/com~apple~CloudDocs/Ledge
    stat -f '%Sm  %z bytes  %N' -t '%F %T' inbox.md
    head -20 inbox.md
    cat capture/drop.md

Expected: the newest day header and entry at the top of `inbox.md` include the
capture he made today on the Mac. If it is there, the Mac wrote correctly and the
problem is downstream of the Mac. If it is not there, the Mac app failed to save
and this is not a sync problem at all; go read the panel header for
"not saved yet, will retry". `drop.md` should normally be empty; anything in it
is an unfolded capture.

**Step 4 [SHANKY].** Look for iCloud placeholders on the Mac side:

    find ~/Library/Mobile\ Documents/com~apple~CloudDocs/Ledge -name '*.icloud' -o -name '.*.icloud'

Expected: no output. Any output means the Mac itself is holding an evicted file.

**Step 5 [SHANKY], iPhone, unlocked.** Open Ledge and record three things
exactly, without touching anything:

- the top-left folder glyph: a plain folder, or a folder with a question mark
- any amber banner text, verbatim
- any muted "N captures waiting" line, verbatim

Interpretation: question mark plus "lost access" is failure mode A. Plain folder
with no banner and stale content is failure mode J. A waiting line is failure
mode D. Write down which one; the rest of the runbook branches on it.

**Step 6 [SHANKY], iPhone.** Files app > Browse > iCloud Drive > Ledge. Look at
`inbox.md`.

Expected when healthy: black text, no cloud badge. If it is grey with a cloud and
down-arrow badge, that is the dataless placeholder from failure mode C. Tap it
once to force the download and wait for the badge to clear. Then return to Ledge
and pull down to refresh.

If the badge never clears, the transport is wedged. Continue to step 7.

**Step 7 [SHANKY], Mac, his own Terminal.** Restart the iCloud daemons:

    killall bird fileproviderd

They restart automatically within seconds. Confirm:

    ps -Ao pid,etime,comm | grep -E 'bird|fileproviderd' | grep -v grep

Expected: fresh elapsed times, under a minute. Note that as of 2026-09-03 09:59
these processes had been running since the 2026-08-31 boot (etime `02-17:00:55`),
so they had not been restarted at any point during this incident. Wait two
minutes, then repeat step 6.

**Step 8 [SHANKY].** Prove Mac to phone with a token. On the Mac, press
Option+Space and capture a line containing a unique string, for example
`sync probe 0903a`. Dismiss the panel. Then:

    grep -n 'sync probe 0903a' ~/Library/Mobile\ Documents/com~apple~CloudDocs/Ledge/inbox.md

Expected: one match. Then open Ledge on the iPhone and pull to refresh. Expected:
the probe appears within a few seconds. Record the wall-clock delay.

**Step 9 [SHANKY].** Prove phone to Mac, which is the half that is easy to
forget. BRAND-SURFACES.md line 118 requires verifying a capture round-trips
**both** ways. On the iPhone, capture `sync probe 0903b`. Then on the Mac:

    grep -n 'sync probe 0903b' ~/Library/Mobile\ Documents/com~apple~CloudDocs/Ledge/inbox.md

Expected: one match within a minute or two. Also summon the Mac panel and confirm
it is visible there, tagged `· iPhone`.

**Step 10 [SHANKY], only if step 8 still fails.** Tap the folder icon in Ledge on
the iPhone and re-pick iCloud Drive > Ledge. He already did this once today; if
it fails a second time, record that, because it is a second independent data
point that the bookmark is not the cause.

**Step 11 [SHANKY], last resort.** Back the folder up first:

    cp -R ~/Library/Mobile\ Documents/com~apple~CloudDocs/Ledge ~/Desktop/Ledge-backup-$(date +%Y%m%d-%H%M)

Then on the iPhone, Settings > Apple Account > iCloud > iCloud Drive, toggle off
and back on. This can evict local copies, which is why the backup comes first.

**Step 12 [MODEL].** Only once steps 8 and 9 both pass, and not before, begin
implementing. Order: M1, M3, M2, M6, M4, M5 from section 5. Run the core tests
after each change:

    cd ~/Projects-with-Claude/ledge/core && swift test

Expected: 41 tests pass (41 `func test` declarations exist in
`core/Tests/LedgeCoreTests/LedgeCoreTests.swift`).

**Step 13 [SHANKY].** Rebuild and reinstall, then immediately re-run steps 8 and
9. The whole point of M5 is that a deploy must not be trusted until a round trip
is proven.

    cd ~/Projects-with-Claude/ledge && ./scripts/deploy.sh all

**Step 14 [MODEL].** Re-verify every claim you intend to write down by running
the check again. Then update `CHANGELOG.md` under Unreleased, add the new quirk
to BRAND-SURFACES.md, run the pre-push gate, commit and push through `osascript`,
and run the post-push audit. See section 0.

---

## 8. Evidence appendix

Commands run on the Mac on 2026-09-03 between 09:50 and 10:05, and their results.

- `git status --porcelain` : empty. `git log -1` : `2217305 2026-09-03 08:54:09
  +0530 Restamp brand provenance for canonical public commit 22a11bc`.
  `origin/main` at the same commit.
- `ls -l /tmp/ledge-*` : `ledge-devices.json` 6736 bytes Sep 3 07:58,
  `ledge-install.log` 451 bytes Sep 3 07:59, `ledge-iosbuild.log` 0 bytes
  Sep 3 07:58, `ledge-macbuild.log` 263 bytes Sep 2 20:47.
- `cat /tmp/ledge-install.log` : tunnel acquired 07:58:46, developer disk image
  services enabled, `App installed: bundleID: com.shashankkarpal.ledge.watchkitapp`.
  Note the script overwrites this log per install call, so only the last install
  (the Watch) is visible.
- devices seen by `devicectl` : `Shashank's 16 Pro Max` (iOS, iPhone 16 Pro Max)
  and `Shashank's Ultra 1` (watchOS, Apple Watch Ultra); both `disconnected` now.
- `ls -ld /Applications/Ledge.app` : Sep 2 20:47. `pgrep -lf Ledge` : pid 56641.
- `/usr/libexec/PlistBuddy -c Print /Applications/Ledge.app/Contents/Info.plist` :
  `com.shashankkarpal.ledge.mac`, `CFBundleShortVersionString = 0.4.1`,
  `LSUIElement = true`.
- `defaults read com.shashankkarpal.ledge.mac` :
  `deviceLabel = "MacBook M4"`, `ledge.morningShownDay = "2026-09-03"`.
- `ls -la ~/Library/Mobile Documents/com~apple~CloudDocs/Ledge` :
  `Operation not permitted`.
- `brctl status` : `Error Domain=BRCloudDocsErrorDomain Code=141 "Access denied"`.
- `sw_vers` : macOS 26.6.2, build 25G83. `uptime` : up 2 days, 17:01.
- `ps -Ao pid,etime,comm` : `cloudd` pid 623, `bird` pid 689, `fileproviderd`
  pid 700, all etime `02-17:00:5x`.
- `/Library/Receipts/InstallHistory.plist`, last 8 entries : Tailscale
  2026-08-18, XProtect 5356 on 08-19 and 08-20, XProtect 5357 on 08-26 and 08-27,
  XProtect 5358 on 09-02, Logitech RightSight and Logi Plugin Service
  2026-09-03 01:15.
- `ls -l <private-ops-repo>/scripts/` : `run-boundary-gates.sh`
  and `audit-postpush.sh` both present and executable;
  `design/brand/OPS-PRIVATE.md` present, 26707 bytes, modified 2026-09-03 08:52.
- `grep -c "func test" core/Tests/LedgeCoreTests/LedgeCoreTests.swift` : 41.
- tree-wide grep for `NSFilePresenter|FSEvent|presentedItem|DispatchSource` :
  matches only `NSMetadataQuery` in `apps/mac/Sources/AppDelegate.swift`.

Documents read in full: `docs/spec.md`, `docs/STATUS-2026-08-17.md`,
`docs/ROADMAP-REDTEAM-2026-08-17.md`, `docs/STATE.md`, `CHANGELOG.md`,
`README.md`, `CLAUDE.md`, `scripts/deploy.sh`, `scripts/seven-day-gate.sh`,
`core/Sources/LedgeCore/{Store,Inbox,Spool,Settings}.swift`,
`apps/ios/Sources/Model/{AppModel,SpoolWriter}.swift`,
`apps/ios/Sources/{LedgeApp,SessionManager}.swift`,
`apps/ios/Sources/Views/{RootView,InboxView}.swift`,
`apps/ios/WatchSources/WatchSessionManager.swift`,
`apps/mac/Sources/{AppDelegate,PanelContent}.swift`,
`~/Projects-with-Claude/shashankkarpal/design/brand/BRAND-SURFACES.md`,
`~/Projects-with-Claude/_claude-chats/kk1/2026-08-19_0921_kk1-cowork_ledge-sync-incident-sop.md`,
`~/Projects-with-Claude/_claude-chats/kk1/2026-09-01_1837_kk1-cowork_m4-rename-runbook-handoff.md`.

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

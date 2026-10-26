# Sync incident ledger

The reviewed record of every line in `.ledge/incidents.log`, the content-free
incident log both apps keep inside the notes folder
(`core/Sources/LedgeCore/Incidents.swift`). It is the evidence the CloudKit
decision waits on: the owner lifted the CloudKit ban on 2026-09-04, with no
migration until this log carries two to four weeks of evidence under real use.

Each review copies the log's fields as they are, adds what the code says they
mean, and appends a row. A review reads only `incidents.log`, which holds no
capture text by design; it never opens `inbox.md`, `notes/`, `attic/` or the
local backups to explain a line.

Last review: 2026-10-26. The log held 3 lines; its last write was 2026-09-25
16:31 UTC (file modification time).

## How to read a line

- A `disagreement` line is written by the observer once a peer heartbeat less
  than 15 minutes old has shown a different inbox digest for at least 5 minutes
  (`LedgeStore.evaluatePeer`: `liveWindow` 15 minutes, `disagreementGrace`
  300 seconds). `startedAt` is when the observer first saw the mismatch, not
  when the line was written.
- `endedAt` is set when that condition stops being true: either the two
  devices agree again, or the peer's heartbeat gets older than 15 minutes. The
  log does not record which of the two happened.
- `secondsAfterInstall` counts from `.ledge/last-install.txt`, which only
  `scripts/deploy.sh` writes. A Mac install from Homebrew or the release zip
  does not stamp it. (The comment on `lastInstallURL` in `Store.swift` also
  names the apps as writers; no app writes the file.)
- On a line observed by the iPhone, `secondsAfterInstall` compares the Mac's
  install stamp with the phone's clock, so it is good to a few seconds, not
  better. That is fine for the question it exists to answer: hours or days
  after an install.
- All times are UTC, as the log stores them.

## Lines

| # | Kind | Observer | Peer | Version | Start (UTC) | End (UTC) | Duration | After the last deploy.sh install | Open? |
|---|---|---|---|---|---|---|---|---|---|
| 1 | disagreement | iPhone | MacBook M4 | 0.5.0 | 2026-09-04 04:32:28 | 2026-09-04 04:37:49 | 5 min 21 s | 0.5 s | closed |
| 2 | disagreement | iPhone | MacBook M4 | 0.5.1 | 2026-09-04 04:45:52 | 2026-09-04 04:51:10 | 5 min 18 s | -2.8 s | closed |
| 3 | disagreement | MacBook M4 | iPhone | 0.5.2 | 2026-09-25 16:21:00 | 2026-09-25 16:31:00 | 10 min 0 s | 964,591 s (11.2 days) | closed |

Lines 1 and 2 were written during the 0.5.0 and 0.5.1 installs themselves:
they start within seconds of the install stamp (the minus sign on line 2 is
the phone's clock against the Mac's, see above).

## Review of line 3 (2026-10-26)

- Kind and devices: a disagreement seen by the Mac, with the iPhone as the
  peer, on 0.5.2.
- Duration: exactly 10 minutes, then closed. Nothing is open, and no line has
  been written since.
- Time since install: 11.2 days after the last `deploy.sh` install, the
  iPhone and Watch install of 2026-09-14 at 12:24 UTC. It is the first line
  that did not begin within seconds or hours of a reinstall.
- What it shows about the reinstall hypothesis
  (`docs/SYNC-RELIABILITY-BRIEF.md`, section 4): nothing either way. It did
  not follow an install, and it healed by itself in 10 minutes, unlike the
  multi-hour stalls of 2026-08-19 and 2026-09-03.
- Inference, not proven: a 10-minute mismatch that clears on its own fits one
  change taking a few minutes to cross iCloud, or the phone going quiet after
  a short session. The log cannot tell these apart (see How to read a line).
- Consequence: line 3 gives no reason for an iOS deploy round. It belongs in
  the CloudKit evidence as one short, self-healing disagreement under
  ordinary use.

## Known limits of the instrument

Recorded here instead of fixed, because a review changes no app code:

1. The close reason (agreement or a quiet peer) is not stored.
2. The install stamp comes only from `deploy.sh`.
3. A quiet log is evidence of healthy sync only for periods when both apps
   were running.

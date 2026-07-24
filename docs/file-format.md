# Ledge file format, the normative contract

Everything in Ledge is plain UTF-8 Markdown. Any tool that respects this contract can read and write Ledge data. The `.ledge/` folder is machine state, always regenerable, never precious.

## Folder layout

```
Ledge/
  inbox.md            THE capture target
  notes/              named notes, flat, no hierarchy
    2026-07-19-globe-workshop.md
  attic/              aged inbox days and archived notes
    2026-06.md        inbox days aged out, grouped by month
    notes/            archived notes
  assets/             pasted images, named yyyy-MM-dd-HHmmss.ext
  capture/
    drop.md           append-only spool written by Shortcuts and the watch relay
  .ledge/
    settings.json     app settings
    index.json        disposable search cache (delete freely)
```

## inbox.md

```
## 2026-07-19
### 09:42
Entry text. Any Markdown. Multiple lines allowed.

- [ ] checkboxes are tracked as open loops

### 08:15
Another entry.

## 2026-07-18
### 22:03
Yesterday's last thought.
```

Rules:

1. A day header is exactly `## yyyy-MM-dd` on its own line. Anything else starting with `##` is ordinary content.
2. An entry header is exactly `### HH:mm` (24-hour) on its own line, inside a day. Anything else starting with `###` is ordinary content.
3. Days are ordered newest first. Entries within a day are ordered newest first. Apps prepend.
4. Entry body is every line until the next entry header, day header, or end of file. Trailing blank lines are trimmed on write; a single blank line separates entries.
5. Text before the first day header is preamble and must be preserved verbatim by any writer.
6. Writers must not reorder or rewrite entries they did not touch.

## capture/drop.md (the spool)

Written only by capture surfaces that cannot safely edit inbox.md (Shortcuts, watch relay). Format, one capture per marker:

```
[[2026-07-19 14:05]] Picked-up thought from the phone.
[[2026-07-19 14:20]] A capture
that spans multiple lines, until the next marker.
```

A marker is `[[yyyy-MM-dd HH:mm]] ` at the start of a line. Text without a leading marker at the top of the file is treated as one capture stamped with the file's modification time. Apps drain the spool by folding every capture into inbox.md (correct day, sorted by time) and then truncating drop.md to empty. Single-writer principle: apps own inbox.md, capture surfaces own drop.md; this is what keeps iCloud conflicts away.

## notes/

Free-form Markdown files. Display title is the first non-empty line, stripped of leading `#` marks. Filenames are `yyyy-MM-dd-slug.md` at creation and stable afterwards; renaming content does not rename files.

## attic/

Aging: inbox day sections older than `agingDays` (default 30) are moved verbatim, headers included, into `attic/yyyy-MM.md` (the month of the day being moved), appended at the end. Nothing is deleted; the Attic is searched by the app like everything else. Archived notes move to `attic/notes/` unchanged.

## .ledge/settings.json

```json
{
  "panelWidth": 380,
  "agingDays": 30,
  "hotkey": { "keyCode": 49, "modifiers": "option" },
  "theme": "system"
}
```

Unknown keys must be preserved. Absent file means all defaults.

## Conflict rule

If iCloud produces a conflict copy of inbox.md, readers union-merge at entry level (entries are timestamped, so the merged set is deduplicated by day + time + exact text) and surface one calm notice. Never a dialog, never data loss.

## Device attribution (added 2026-07-24)

Entry headers and spool markers may carry an optional source-device suffix,
separated by " · " (space, middle dot U+00B7, space):

    ### 09:42 · iPhone
    [[2026-07-24 09:42 · Apple Watch]] dictated text

The device tag is free text without newlines: iPhone, iPad, Apple Watch, or a
Mac label (default: the computer name; override per machine with
`defaults write com.example.ledge.mac deviceLabel "MacBook M4"`).
Headers without the suffix remain valid. The tag is not part of entry identity:
dedupe stays day + minute + text. All app capture surfaces write it as of v0.2;
hand-built Shortcuts recipes may omit it and stay valid.

## Concurrency contract (added 2026-07-24, implemented in LedgeStore)

1. A read never mistakes "not downloaded from iCloud yet" for "empty"
   (placeholder detection, forced download, notDownloaded error).
2. A save never blindly overwrites bytes that changed since the last read;
   it folds its entries into the disk state instead (mtime read-stamps).
3. iCloud conflict versions of inbox.md are folded back in on every load and
   marked resolved: last-writer-wins can hide entries but never lose them.
4. The spool is truncated by exactly the content that was folded.
5. iOS keeps a local capture journal until each capture is confirmed present
   in a loaded inbox; unconfirmed captures are folded back on refresh.

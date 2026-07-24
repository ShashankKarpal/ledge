# Ledge

A free, open-source, local-only, ADHD-first sidebar notepad for Mac, iPhone, and iPad.

**Built by Claude (Anthropic).** This app was designed and written end to end by Claude, from the research and architecture spec through every line of code, at the direction of Shashank Karpal. That is not a footnote, it is the project's origin story.

## What it is

Ledge lives at the edge of your Mac screen. One hotkey (Option+Space by default) slides it in with the cursor already blinking on a fresh, timestamped entry in a single inbox. Esc tucks it away. No titles, no folders, no filing decisions, no accounts, no telemetry, no red badges, no streaks. Your notes are plain Markdown files in a folder you can see, open in any editor, and sync for free through iCloud Drive.

The design constraint is ADHD-C. Every decision is tested against: reduce capture friction to near zero, minimize decisions, prevent lost thoughts, avoid overwhelm, make re-finding effortless, nudge gently or not at all. The full rationale lives in `docs/spec.md`.

## The pieces

| Piece | What it does |
|---|---|
| `core/` | LedgeCore, a Swift package: the file format, inbox engine, spool drain, fuzzy search, Attic aging, Open Loops scanner. Pure Foundation, fully unit tested. |
| `apps/mac/` | The Mac sidebar app. AppKit + Carbon hotkey + non-activating panel. Builds with one script, no Xcode project needed. |
| `apps/ios/` | iPhone and iPad app (SwiftUI) plus the watchOS capture relay. Generated with XcodeGen. |
| `shortcuts/` | The capture net: an iPhone/iPad Shortcuts recipe that appends to your inbox even when no app is installed or signed. |
| `docs/` | The architecture spec and the normative file-format contract. |

## Quick start, Mac (5 minutes)

Requires: macOS 13+, Xcode Command Line Tools (`xcode-select --install`).

```bash
cd ledge
./scripts/build-mac.sh          # compiles LedgeCore + the app, assembles build/Ledge.app
open build/Ledge.app            # menu bar icon appears; press Option+Space
```

The first launch creates your notes folder at `~/Library/Mobile Documents/com~apple~CloudDocs/Ledge` (iCloud Drive) or `~/Documents/Ledge` if iCloud Drive is unavailable. To start at login: System Settings > General > Login Items > add Ledge.app.

## Quick start, iPhone/iPad

1. Set up the capture net first (works today, no app needed): see `shortcuts/README.md`. It appends captures to `capture/drop.md` in your Ledge folder; the apps fold them into the inbox automatically.
2. For the full app: `brew install xcodegen`, then `cd apps/ios && xcodegen generate`, open `Ledge.xcodeproj` in Xcode, select your personal team (free Apple ID works), and run on your device. On first launch, pick your Ledge folder in the folder picker (choose the one in iCloud Drive so Mac and iPhone share notes).
3. Free-tier signing expires every 7 days; the capture net keeps working regardless. An Apple Developer Program membership extends signing to a year and enables TestFlight/App Store.

## Where your notes live (privacy)

At rest: plain `.md` files in your Ledge folder (iCloud Drive or local). Nothing else, nowhere else. No accounts, no analytics, no network calls except iCloud's own file sync performed by the OS. For stronger cloud encryption enable Advanced Data Protection on your Apple ID, or point Ledge at a local folder for zero cloud presence. The `.ledge/` subfolder holds a disposable search index and settings; delete it any time, it rebuilds.

## Keyboard map (Mac)

| Key | Action |
|---|---|
| Option+Space | Summon / dismiss the sidebar |
| Esc | Tuck away (autosaves, removes an untouched empty entry) |
| Cmd+K | Search (fuzzy, recency-weighted) |
| Cmd+L | Open Loops (every unchecked box, grouped by age) |
| Cmd+P | Notes list |
| Cmd+N | New named note |
| Click a checkbox | Toggle it |

## The file format (yours forever)

```
## 2026-07-19
### 09:42
The thought, exactly as it fell out.

- [ ] a loop Ledge will gently resurface
```

Days newest-first, entries newest-first, timestamps automatic. The full contract is in `docs/file-format.md`. Any Markdown editor can read and write these files; Ledge never locks you in.

## License and credit

MIT. Built by Claude (Anthropic Claude, Fable/Opus class models) with Shashank Karpal as director and first user. If you fork this, keep the attribution line in the About screen honest about what wrote it.

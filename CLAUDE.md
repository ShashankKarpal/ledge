# CLAUDE.md

Read this first, every session. Facts in this file override anything older,
including docs/spec.md. If you find yourself about to ask the owner a question,
check here first.

## Project facts

- Ledge is a free, MIT-licensed, open source, local-only, ADHD-first sidebar
  notepad for Mac, iPhone, iPad, and Apple Watch. Plain Markdown in the owner's
  own iCloud Drive folder. No accounts, no telemetry, no server.
- Single user in practice: the owner is the only real user. There are no
  enrolled beta testers. Weigh roadmap and build decisions against the owner's
  observed usage, never an imagined audience
  (see docs/ROADMAP-REDTEAM-2026-08-17.md).
- The owner is a non-developer. All code is written by Claude. Explain in plain
  language and give exact runnable commands.
- This is a personal portfolio project, unrelated to the owner's employer.

## Decisions on record (owner-made, FINAL until he reopens them)

- The iPhone Action Button stays on Workout. Never plan, suggest, or document
  Action Button integration. The watch face complication and Siri are the only
  watch triggers.
- TestFlight is killed (red-team C5), and the would-be first tester is on hold
  with it. Do not propose either.
- Final-five item 5, the distribution decision, is ON HOLD by the owner's
  explicit choice: no nags, no deadlines; it revisits only when he raises it.
  This supersedes the "default on silence is archive" framing in
  docs/ROADMAP-REDTEAM-2026-08-17.md.
- Build order approved 2026-08-17: item 2 remainder, then item 1
  (capture-trust as scope-capped), then item 3 (VERSION single source plus CI
  drift gate); item 4, the seven-day gate, initiates after item 3 lands and
  governs all feature work after it.
- 2026-09-04: the CloudKit ban is lifted, but there is NO migration until
  .ledge/incidents.log carries two to four weeks of evidence under real use
  (reviewed in docs/INCIDENT-LEDGER.md). The destination is Option C: the
  CloudKit private database as the store, with a one-way Markdown export.
  Pin the development or production container before any build. Keep the
  WatchConnectivity relay.
- 2026-09-04: dictation is not a Ledge feature. The owner dictates with a
  system-wide dictation tool; Ledge has no speech code.
- Engineering rules (2026-09-04 and 2026-09-14): never destroy the durable
  copy before the replacement is on disk; never rewrite in place when an
  append will do; never compare a timestamp from one device against a clock
  on another; monitoring must not tax the transport it measures; no new code
  without an observed failure. Recovery is observational first, and a restore
  writes only into a NEW folder. Any LedgeCore change is typechecked for
  watchOS and iOS (scripts/check-core-platforms.sh) before a deploy or a
  release. scripts/notarize.sh is the only release path, and the README badge
  and download name move only in the release commit.
- 2026-09-14: Claude chooses the features and their order, within the rules
  above.
- 2026-10-11: the 30-second tour GIF, the screenshots and the Reddit post are
  the owner's, for later. Do not raise them.
- Never press the owner about daily capture.

## Repo visibility and publish policy

- This repo is PUBLIC by deliberate decision (pushed public 2026-07-24;
  distribution rationale settled 2026-07-29: GitHub releases are the channel,
  the App Store is deferred). Do not ask whether it should be public, and do
  not treat publicness itself as a risk to escalate.
- Acceptable to publish: source, design assets, build scripts, status and
  roadmap docs, usage dates and entry counts, device labels like "iPhone" or
  "MacBook M4".
- Never publish: contents of live inbox entries, any medical or diagnosis
  detail about the owner, the Apple Team ID, absolute /Users/... paths, real
  email addresses (commits use the GitHub noreply author only), credentials of
  any kind. History was rewritten once (2026-08-02) to remove exactly this
  class of material. Do not reintroduce it.

## Signing and distribution reality

- The owner holds a paid Apple Developer Program membership (individual,
  active since 2026-07-27, provisioning profiles valid to 2027-07). There is
  NO seven day re-signing wall and NO free-provisioning constraint on the
  owner's builds. Never warn about weekly re-signing.
- docs/spec.md predates the membership. Its free-tier signing sections
  (4.1-4.4, the findings table rows on free provisioning and AltStore, and the
  M4 milestone signing note) are historical, kept only so forkers without a
  membership can still build and sideload. Do not plan from them.
- Mac distribution: notarized Developer ID zips on GitHub Releases. The Team
  ID is never committed; it comes from the local environment.
- Owner device deploys: scripts/deploy.sh.

## Platforms and devices

- Targets: macOS (AppKit, raw swiftc via scripts/build-mac.sh), iOS and
  watchOS (SwiftUI, XcodeGen from apps/ios/project.yml), WidgetKit extension.
  Shared logic lives in the LedgeCore Swift package (core/), which carries the
  unit tests.
- Owner devices: M4 Pro MacBook (primary), iPhone, iPad, Apple Watch.
- Mac bundle id: com.shashankkarpal.ledge.mac (defaults domain of the same
  name; the com.example domain is dead as of v0.4.1).

## Where prior history lives (do not reconstruct from scratch)

- Live cross-session state, read first: this project's handoff file in the
  fleet's private cross-session handoff repo; the fleet root CLAUDE.md (one
  directory up) names that repo and its handoffs/ path. Write or refresh
  the handoff at session end, always.
- Session logs: ../_claude-chats/ (kk1 and kk2 subfolders; filenames contain
  "ledge").
- Knowledge dumps v1 to v5, the densest project reasoning, deliberately purged
  from this repo's public history: ../_private/ledge-knowledge-dumps/ (five
  files, carried by the nightly projects backup). There is no second copy:
  ../_archive/ledge-knowledge-dumps/, named here until 2026-10-26, does not
  exist. Dump v2's correction banner and dump v3 section 1 record the signing
  transition.
- Newest dated doc wins. As of 2026-08-17: status is
  docs/STATUS-2026-08-17.md, roadmap is docs/ROADMAP-REDTEAM-2026-08-17.md
  (the final five and build order). Sync incidents: docs/INCIDENT-LEDGER.md
  (last review 2026-10-26).

## Operating rules

7. Never push without the owner's explicit confirmation in the current
   session.
8. At session end: refresh the bridge handoff, write a session log, and if the
   owner had to answer a question this file should have answered, add the
   answer to this file in the same session.
9. The seven-day gate governs feature work (active since 2026-08-17, final-five
   item 4). Before starting any NEW feature, run
   `bash scripts/seven-day-gate.sh`; if it reports CLOSED, the feature does not
   start. Bug fixes, capture reliability, docs, and maintenance are always
   exempt. The script is pull-only: never wire it into CI, a badge, or any
   recurring surface, and never nag the owner about the run length.

## Security and hygiene rules (every agent session)

1. Never commit secrets: no API keys, tokens, passwords, private keys, or
   .env files. Templates belong in *.example files with placeholder values
   only.
2. Untracking or deleting a file does not remove it from git history. If a
   secret ever lands in a commit: rotate it at the provider first, then
   rewrite history with git filter-repo.
3. At the end of each session: delete unused code, merge duplicate helpers,
   remove commented-out blocks. Use deterministic tools (linters, dead-code
   finders) and review the diff before deleting.
4. Keep .gitignore covering .env, .env.*, and secrets.* (with !*.example
   exemptions). Never weaken it.
5. The gitleaks CI workflow (.github/workflows/gitleaks.yml) stays. Never
   remove or bypass it.
6. After editing any file, verify the edit by reading the changed content back
   out of the file before committing. Never rely on a proxy check (lint,
   generate, build) that would also pass on the unedited file. Structured
   files (plist, XML, JSON, YAML) are edited with structured tools only
   (PlistBuddy, plutil, a real parser), never with regex substitutions piped
   through nested shell or osascript quoting.

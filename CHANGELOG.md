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

- Mac editor marks text as saved only after the write succeeds; a failed save now shows "not saved yet, will retry" instead of "captured" and keeps the text for the next commit (2026-09-02 fleet audit).
- iOS capture journal confirms own captures by minute stamp and device, so an entry edited on the Mac is no longer re-added as a duplicate, and a capture deleted elsewhere is not resurrected.
- iOS balances security-scoped folder access (one active scope per root) so repeated reconnects can no longer exhaust the per-process cap and show "lost access" until relaunch.
- Captured text that contains header-shaped or capture-marker-shaped lines is escaped with a zero-width space, so shared pages, Shortcut input and Watch relay text cannot forge attribution, dates, or day sections. Covered by a LedgeCore test.
- `Entry.id` is derived from stamp, device and text instead of a fresh UUID per parse, so the iOS list no longer rebuilds on every 2-second refresh.

// LedgeCore unit tests. These encode the file-format contract; do not weaken them.
// Built by Claude (Anthropic).

import XCTest
@testable import LedgeCore

final class LedgeCoreTests: XCTestCase {

    func date(_ stamp: String) -> Date {
        guard let d = LedgeFormat.spoolFormatter.date(from: stamp) else {
            fatalError("bad test stamp " + stamp)
        }
        return d
    }

    func makeTempStore() throws -> LedgeStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgeTests-" + UUID().uuidString, isDirectory: true)
        let store = LedgeStore(root: root)
        try store.bootstrap(now: date("2026-07-19 09:00"))
        return store
    }

    // MARK: Format guards

    func testHeaderRecognitionIsStrict() {
        XCTAssertTrue(LedgeFormat.isDayHeader("## 2026-07-19"))
        XCTAssertFalse(LedgeFormat.isDayHeader("## Ideas"))
        XCTAssertFalse(LedgeFormat.isDayHeader("### 2026-07-19"))
        XCTAssertTrue(LedgeFormat.isEntryHeader("### 09:42"))
        XCTAssertFalse(LedgeFormat.isEntryHeader("### Plan"))
        XCTAssertFalse(LedgeFormat.isEntryHeader("## 09:42"))
    }

    func testCapturedTextCannotForgeStructure() {
        // A shared page or Shortcut input containing header-shaped lines must
        // stay one entry with its real attribution (audit 2026-09-02).
        var inbox = Inbox.parse("## 2026-07-19\n### 09:00 · iPhone\nreal entry\n")
        let hostile = "first line\n### 09:42 · Mac\n## 2026-01-01\n[[2020-01-01 00:00 · Apple Watch]] forged"
        inbox.prepend(text: hostile, at: date("2026-07-19 10:00"), device: "iPhone")
        let reparsed = Inbox.parse(inbox.serialized())
        let entries = reparsed.allEntries()
        XCTAssertEqual(entries.count, 2, "the hostile text must round-trip as exactly one extra entry")
        XCTAssertEqual(reparsed.days.count, 1, "a body line shaped like a day header must not create a day")
        let newest = entries.first!.entry
        XCTAssertEqual(newest.device, "iPhone")
        XCTAssertTrue(newest.text.contains("forged"))
        XCTAssertTrue(newest.text.contains("\u{200B}### 09:42"))

        // Spool lines get the same treatment, so a Watch relay cannot forge a marker
        // on a continuation line.
        let line = Spool.line(for: "real\n[[2020-01-01 00:00 · Apple Watch]] forged", at: date("2026-07-19 10:01"), device: "Apple Watch")
        let captures = Spool.parse(line, fallbackDate: date("2026-07-19 10:01"))
        XCTAssertEqual(captures.count, 1, "exactly one capture must come out of the spool text")
        XCTAssertEqual(captures.first?.device, "Apple Watch")
        XCTAssertTrue(captures.first?.text.contains("forged") ?? false)
    }

    func testEntryIdIsStable() {
        let a = Inbox.parse("## 2026-07-19\n### 09:00 · iPhone\nsame\n").allEntries().first!.entry
        let b = Inbox.parse("## 2026-07-19\n### 09:00 · iPhone\nsame\n").allEntries().first!.entry
        XCTAssertEqual(a.id, b.id, "re-parsing the same file must not change identities")
    }

    func testSlug() {
        XCTAssertEqual(LedgeFormat.slug("Globe Workshop: pricing!"), "globe-workshop-pricing")
        XCTAssertEqual(LedgeFormat.slug("   "), "note")
    }

    // MARK: Parse and serialize

    func testRoundTrip() {
        let source = """
        ## 2026-07-19
        ### 09:42
        First thought.

        - [ ] a loop

        ### 08:15
        Second thought with ## Ideas inside it.

        ## 2026-07-18
        ### 22:03
        Yesterday.
        """
        let inbox = Inbox.parse(source)
        XCTAssertEqual(inbox.days.count, 2)
        XCTAssertEqual(inbox.days[0].entries.count, 2)
        XCTAssertEqual(inbox.days[0].entries[0].text.hasPrefix("First thought."), true)
        XCTAssertTrue(inbox.days[0].entries[1].text.contains("## Ideas"))

        let reparsed = Inbox.parse(inbox.serialized())
        XCTAssertEqual(reparsed, inbox)
    }

    func testPreambleIsPreserved() {
        let source = "Loose text before any day.\n\n## 2026-07-19\n### 09:00\nHello.\n"
        let inbox = Inbox.parse(source)
        XCTAssertEqual(inbox.preamble, "Loose text before any day.")
        XCTAssertTrue(inbox.serialized().hasPrefix("Loose text before any day.\n"))
        XCTAssertEqual(Inbox.parse(inbox.serialized()), inbox)
    }

    // MARK: Prepend ordering

    func testPrependKeepsNewestFirst() {
        var inbox = Inbox()
        inbox.prepend(text: "morning", at: date("2026-07-19 08:00"))
        inbox.prepend(text: "later", at: date("2026-07-19 14:00"))
        inbox.prepend(text: "yesterday", at: date("2026-07-18 23:00"))
        inbox.prepend(text: "tomorrow", at: date("2026-07-20 07:00"))

        XCTAssertEqual(inbox.days.map(\.day), ["2026-07-20", "2026-07-19", "2026-07-18"])
        XCTAssertEqual(inbox.days[1].entries.map(\.text), ["later", "morning"])
    }

    func testRemoveEmptyEntries() {
        var inbox = Inbox()
        inbox.prepend(text: "", at: date("2026-07-19 09:00"))
        inbox.prepend(text: "keep me", at: date("2026-07-19 09:05"))
        inbox.removeEmptyEntries()
        XCTAssertEqual(inbox.allEntries().map { $0.entry.text }, ["keep me"])
    }

    // MARK: Spool

    func testSpoolParseWithMarkersAndMultiline() {
        let raw = """
        [[2026-07-19 14:05]] Phone thought.
        [[2026-07-19 14:20]] A capture
        that spans two lines.
        """
        let captures = Spool.parse(raw, fallbackDate: date("2026-07-19 15:00"))
        XCTAssertEqual(captures.count, 2)
        XCTAssertEqual(captures[0].text, "Phone thought.")
        XCTAssertEqual(captures[1].text, "A capture\nthat spans two lines.")
    }

    func testSpoolUnmarkedTextUsesFallback() {
        let captures = Spool.parse("raw unmarked line", fallbackDate: date("2026-07-19 15:00"))
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures[0].date, date("2026-07-19 15:00"))
    }

    func testDrainFoldsAndDeduplicates() throws {
        let store = try makeTempStore()
        var inbox = try store.loadInbox()
        let line = Spool.line(for: "from the phone", at: date("2026-07-19 14:05"))
        try store.writeString(line + "\n" + line + "\n", to: store.spoolURL)

        let added = try store.drainSpool(into: &inbox)
        XCTAssertEqual(added, 1)
        XCTAssertTrue(inbox.allEntries().contains { $0.entry.text == "from the phone" })

        // Spool is truncated after drain.
        let after = try store.readString(store.spoolURL) ?? ""
        XCTAssertEqual(LedgeFormat.trimEdges(after), "")

        // Draining again adds nothing.
        XCTAssertEqual(try store.drainSpool(into: &inbox), 0)
    }

    // MARK: Capture trust (the stale-spool check)

    func testSpoolStatusEmpty() {
        let status = Spool.status("", fallbackDate: date("2026-08-16 13:47"))
        XCTAssertEqual(status, .empty)
        XCTAssertNil(status.waitingLine(now: date("2026-08-17 09:00")))
    }

    func testSpoolStatusCountsAndFindsOldest() {
        let raw = "[[2026-08-16 13:47]] stranded\n[[2026-08-17 08:00]] fresh\n"
        let status = Spool.status(raw, fallbackDate: date("2026-08-17 09:00"))
        XCTAssertEqual(status.count, 2)
        XCTAssertEqual(status.oldest, date("2026-08-16 13:47"))
    }

    func testSpoolStatusStaleThreshold() {
        let status = Spool.status("[[2026-08-17 08:00]] waiting", fallbackDate: date("2026-08-17 08:00"))
        XCTAssertFalse(status.isStale(now: date("2026-08-17 08:59")))
        XCTAssertTrue(status.isStale(now: date("2026-08-17 09:01")))
    }

    func testWaitingLineCopyAndMerge() {
        let fresh = Spool.status("[[2026-08-17 08:59]] one", fallbackDate: date("2026-08-17 09:00"))
        XCTAssertEqual(fresh.waitingLine(now: date("2026-08-17 09:00")), "1 capture waiting")
        let stale = Spool.status(
            "[[2026-08-16 13:47]] one\n[[2026-08-16 14:00]] two",
            fallbackDate: date("2026-08-17 09:00")
        )
        XCTAssertEqual(
            stale.waitingLine(now: date("2026-08-17 09:00")),
            "2 captures waiting since 2026-08-16 13:47"
        )
        let combined = fresh.merged(with: stale)
        XCTAssertEqual(combined.count, 3)
        XCTAssertEqual(combined.oldest, date("2026-08-16 13:47"))
    }

    // MARK: Aging

    func testAgingMovesOldDaysToAttic() throws {
        let store = try makeTempStore()
        var inbox = Inbox()
        inbox.prepend(text: "old thought", at: date("2026-06-01 10:00"))
        inbox.prepend(text: "fresh thought", at: date("2026-07-19 10:00"))

        let moved = try store.age(&inbox, olderThanDays: 30, now: date("2026-07-19 12:00"))
        XCTAssertEqual(moved, 1)
        XCTAssertEqual(inbox.days.map(\.day), ["2026-07-19"])

        let atticContent = try store.readString(store.atticURL.appendingPathComponent("2026-06.md")) ?? ""
        XCTAssertTrue(atticContent.contains("old thought"))
        XCTAssertTrue(atticContent.contains("## 2026-06-01"))
    }

    // MARK: Open loops

    func testOpenLoopsFindsUncheckedOnly() throws {
        let store = try makeTempStore()
        var inbox = Inbox()
        inbox.prepend(text: "- [ ] call Ishan\n- [x] done thing", at: date("2026-07-19 09:30"))
        let loops = store.openLoops(inbox: inbox)
        // The seeded onboarding note adds no loops here because we built a fresh inbox in memory.
        XCTAssertEqual(loops.filter { $0.fileURL == store.inboxURL }.map(\.text), ["call Ishan"])
    }

    // MARK: Search

    func testSearchPrefersRecent() throws {
        let store = try makeTempStore()
        var inbox = Inbox()
        inbox.prepend(text: "kubernetes pricing thought, old", at: date("2026-05-01 09:00"))
        inbox.prepend(text: "kubernetes pricing thought, new", at: date("2026-07-19 09:00"))

        let hits = store.search("kubernetes pricing", inbox: inbox, now: date("2026-07-19 12:00"))
        XCTAssertGreaterThanOrEqual(hits.count, 2)
        XCTAssertTrue(hits[0].snippet.contains("new"))
    }

    func testSearchSubsequenceTolerance() {
        XCTAssertEqual(LedgeStore.matchScore("globe workshop pricing", tokens: ["gwp"]), 0.6)
        XCTAssertEqual(LedgeStore.matchScore("globe workshop", tokens: ["zebra"]), 0)
    }

    // MARK: Settings

    func testSettingsRoundTripPreservesUnknownKeys() throws {
        let store = try makeTempStore()
        let url = store.settingsURL
        let seeded = "{\"panelWidth\": 400, \"futureKey\": \"keep me\"}"
        try seeded.write(to: url, atomically: true, encoding: .utf8)

        var settings = LedgeSettings.load(from: url)
        XCTAssertEqual(settings.panelWidth, 400)
        settings.agingDays = 45
        try settings.save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.contains("futureKey"))
        XCTAssertTrue(raw.contains("45"))
    }

    // MARK: Bootstrap

    func testBootstrapSeedsOnboardingEntry() throws {
        let store = try makeTempStore()
        let inbox = try store.loadInbox()
        XCTAssertEqual(inbox.days.count, 1)
        XCTAssertTrue(inbox.days[0].entries[0].text.contains("Welcome to Ledge"))
    }

    // MARK: Clobber guards (added after the 2026-07-24 incident)

    func makeBareRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgeTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testReadStringThrowsWhenOnlyPlaceholderExists() throws {
        let root = try makeBareRoot()
        let store = LedgeStore(root: root)
        let placeholder = root.appendingPathComponent(".inbox.md.icloud")
        try "".write(to: placeholder, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.readString(store.inboxURL)) { error in
            XCTAssertEqual(error as? LedgeStoreError, .notDownloaded(store.inboxURL))
        }
    }

    func testBootstrapDoesNotSeedOverPlaceholder() throws {
        let root = try makeBareRoot()
        let placeholder = root.appendingPathComponent(".inbox.md.icloud")
        try "".write(to: placeholder, atomically: true, encoding: .utf8)
        let store = LedgeStore(root: root)
        try store.bootstrap(now: date("2026-07-19 09:00"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.inboxURL.path))
    }

    func testSaveInboxMergesWhenDiskChangedSinceLastRead() throws {
        let store = try makeTempStore()
        var mine = try store.loadInbox()
        let external = "## 2026-07-23\n\n### 10:00\n\nExternal entry from another device\n"
        try external.write(to: store.inboxURL, atomically: true, encoding: .utf8)
        mine.prepend(text: "Entry from this device", at: date("2026-07-24 09:00"))
        try store.saveInbox(mine)
        let final = try XCTUnwrap(try store.readString(store.inboxURL))
        XCTAssertTrue(final.contains("External entry from another device"))
        XCTAssertTrue(final.contains("Entry from this device"))
    }

    func testSaveInboxWithoutPriorReadMergesWithDisk() throws {
        let seeded = try makeTempStore()
        let fresh = LedgeStore(root: seeded.root)
        var mine = Inbox()
        mine.prepend(text: "Blind writer entry", at: date("2026-07-24 09:05"))
        try fresh.saveInbox(mine)
        let final = try XCTUnwrap(try fresh.readString(fresh.inboxURL))
        XCTAssertTrue(final.contains("Welcome to Ledge"))
        XCTAssertTrue(final.contains("Blind writer entry"))
    }

    func testSaveInboxWritesDirectlyWhenDiskUnchanged() throws {
        let store = try makeTempStore()
        var mine = try store.loadInbox()
        mine.prepend(text: "Straight save", at: date("2026-07-24 09:10"))
        try store.saveInbox(mine)
        let final = try XCTUnwrap(try store.readString(store.inboxURL))
        XCTAssertTrue(final.contains("Straight save"))
        XCTAssertTrue(final.contains("Welcome to Ledge"))
    }

    func testTruncateSpoolKeepsCapturesAppendedDuringDrain() throws {
        let store = try makeTempStore()
        let consumed = "[[2026-07-24 09:00]] first capture\n"
        let late = "[[2026-07-24 09:01]] arrived mid drain\n"
        try (consumed + late).write(to: store.spoolURL, atomically: true, encoding: .utf8)
        try store.truncateSpool(consumed: consumed)
        let remaining = ((try store.readString(store.spoolURL)) ?? nil) ?? ""
        XCTAssertTrue(remaining.contains("arrived mid drain"))
        XCTAssertFalse(remaining.contains("first capture"))
    }

    func testSaveNotePreservesConflictingDiskVersionInAttic() throws {
        let store = try makeTempStore()
        let url = try store.createNote(title: "Plan", now: date("2026-07-19 09:00"))
        try "# Plan\n\nEdited on another device\n".write(to: url, atomically: true, encoding: .utf8)
        try store.saveNote("# Plan\n\nEdited here\n", to: url, now: date("2026-07-24 09:20"))
        let final = try XCTUnwrap(try store.readString(url))
        XCTAssertTrue(final.contains("Edited here"))
        let kept = try FileManager.default.contentsOfDirectory(atPath: store.atticNotesURL.path)
        XCTAssertTrue(kept.contains { $0.hasPrefix("2026-07-19-plan-") })
    }

    // MARK: Device attribution

    func testDeviceTagRoundTrip() throws {
        let source = "## 2026-07-24\n\n### 09:42 · iPhone\n\nTagged thought.\n\n### 09:40\n\nUntagged thought.\n"
        let inbox = Inbox.parse(source)
        XCTAssertEqual(inbox.days[0].entries[0].device, "iPhone")
        XCTAssertNil(inbox.days[0].entries[1].device)
        let out = inbox.serialized()
        XCTAssertTrue(out.contains("### 09:42 · iPhone"))
        let again = Inbox.parse(out)
        XCTAssertEqual(again.days[0].entries[0].device, "iPhone")
        XCTAssertEqual(again, inbox)
    }

    func testSpoolDeviceTagRoundTrip() throws {
        let line = Spool.line(for: "from the wrist", at: date("2026-07-24 09:00"), device: "Apple Watch")
        XCTAssertEqual(line, "[[2026-07-24 09:00 · Apple Watch]] from the wrist")
        let captures = Spool.parse(line, fallbackDate: date("2026-07-24 09:05"))
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures[0].device, "Apple Watch")
        XCTAssertEqual(captures[0].text, "from the wrist")
        var inbox = Inbox()
        _ = inbox.fold(captures.map { (date: $0.date, text: $0.text, device: $0.device) })
        XCTAssertEqual(inbox.days[0].entries[0].device, "Apple Watch")
    }

    // MARK: Capture delivery ids (bug 2, 2026-08-17: duplicate watch delivery)

    func testSpoolLineWithIDRoundTrip() {
        let line = Spool.line(for: "wrist thought", at: date("2026-08-17 09:27"), device: "Apple Watch", id: "ABC-123")
        XCTAssertEqual(line, "[[2026-08-17 09:27 · Apple Watch · #ABC-123]] wrist thought")
        let captures = Spool.parse(line, fallbackDate: date("2026-08-17 10:00"))
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures[0].id, "ABC-123")
        XCTAssertEqual(captures[0].device, "Apple Watch")
        XCTAssertEqual(captures[0].text, "wrist thought")
    }

    func testSpoolIDWithoutDeviceAndLegacyLinesParse() {
        let withID = Spool.parse("[[2026-08-17 09:27 · #X1]] no device", fallbackDate: date("2026-08-17 10:00"))
        XCTAssertEqual(withID[0].id, "X1")
        XCTAssertNil(withID[0].device)
        let legacy = Spool.parse("[[2026-08-17 09:27 · Apple Watch]] old format", fallbackDate: date("2026-08-17 10:00"))
        XCTAssertNil(legacy[0].id)
        XCTAssertEqual(legacy[0].device, "Apple Watch")
    }

    func testReplyTimeoutDoubleDeliveryIsDeduplicatedAcrossDrains() throws {
        // The reply-timeout double path: the phone receives the live message,
        // the reply times out on the watch, and the queued fallback delivers
        // the same capture again in a LATER batch. Same id both times.
        let store = try makeTempStore()
        var inbox = try store.loadInbox()
        let line = Spool.line(for: "a twin delivery from the wrist", at: date("2026-08-17 09:27"), device: "Apple Watch", id: "DUP-1")

        try store.writeStringInPlace(line + "\n", to: store.spoolURL)
        XCTAssertEqual(try store.drainSpool(into: &inbox), 1)
        try store.saveInbox(inbox)

        // Second delivery arrives after the first batch fully drained.
        try store.writeStringInPlace(line + "\n", to: store.spoolURL)
        XCTAssertEqual(try store.drainSpool(into: &inbox), 0)
        let matches = inbox.allEntries().filter { $0.entry.text == "a twin delivery from the wrist" }
        XCTAssertEqual(matches.count, 1)
    }

    func testIDDedupHoldsEvenWhenTextDedupCannot() throws {
        // Prove the dedup is id-based: mangle the folded entry (as the owner
        // editing it, or corruption, would), so day+minute+text can no longer
        // match, then deliver the duplicate. It must still be dropped.
        let store = try makeTempStore()
        var inbox = try store.loadInbox()
        let line = Spool.line(for: "original text", at: date("2026-08-17 09:27"), device: "Apple Watch", id: "DUP-2")
        try store.writeStringInPlace(line + "\n", to: store.spoolURL)
        XCTAssertEqual(try store.drainSpool(into: &inbox), 1)

        for dayIndex in inbox.days.indices {
            for entryIndex in inbox.days[dayIndex].entries.indices
            where inbox.days[dayIndex].entries[entryIndex].text == "original text" {
                inbox.days[dayIndex].entries[entryIndex].text = "edited by the owner"
            }
        }

        try store.writeStringInPlace(line + "\n", to: store.spoolURL)
        XCTAssertEqual(try store.drainSpool(into: &inbox), 0)
        XCTAssertFalse(inbox.allEntries().contains { $0.entry.text == "original text" })
    }

    func testSameBatchDuplicateIDsFoldOnce() throws {
        let store = try makeTempStore()
        var inbox = try store.loadInbox()
        let line = Spool.line(for: "double in one batch", at: date("2026-08-17 09:30"), device: "Apple Watch", id: "DUP-3")
        try store.writeStringInPlace(line + "\n" + line + "\n", to: store.spoolURL)
        XCTAssertEqual(try store.drainSpool(into: &inbox), 1)
    }

    func testCapturesWithoutIDsStillFoldAndTextDedupStillStands() throws {
        // Negative test: nothing about the id machinery may break Shortcuts
        // captures, which carry no id. Same stamp+text still dedupes.
        let store = try makeTempStore()
        var inbox = try store.loadInbox()
        let line = Spool.line(for: "plain shortcuts capture", at: date("2026-08-17 09:35"))
        try store.writeStringInPlace(line + "\n", to: store.spoolURL)
        XCTAssertEqual(try store.drainSpool(into: &inbox), 1)
        try store.writeStringInPlace(line + "\n", to: store.spoolURL)
        XCTAssertEqual(try store.drainSpool(into: &inbox), 0)
    }

    func testSeenIDLedgerIsCappedAt500() throws {
        let store = try makeTempStore()
        store.recordSeenCaptureIDs((0..<600).map { "ID-\($0)" })
        let seen = store.seenCaptureIDs()
        XCTAssertEqual(seen.count, 500)
        XCTAssertFalse(seen.contains("ID-99"))
        XCTAssertTrue(seen.contains("ID-100"))
        XCTAssertTrue(seen.contains("ID-599"))
    }

    // MARK: Null-byte corruption (bug 3, 2026-08-17: 588-null run in the live inbox)

    func testStrippingNullsRemovesOnlyNulls() {
        let dirty = "keep\u{0000}\u{0000} this · exactly\u{0000}\n[[unchanged]]"
        XCTAssertEqual(LedgeFormat.strippingNulls(dirty), "keep this · exactly\n[[unchanged]]")
        let clean = "no nulls here"
        XCTAssertEqual(LedgeFormat.strippingNulls(clean), clean)
    }

    func testLoadInboxRepairsNullBytesAndCollapsesTheSmuggledDuplicate() throws {
        // Byte-for-byte shape of the live 2026-08-17 corruption: a null run
        // inside the first entry's body, between two copies of the same
        // capture. The nulls made the entry texts unequal, which is how the
        // duplicate got past fold's dedupe in the first place.
        let store = try makeTempStore()
        let nulls = String(repeating: "\u{0000}", count: 588)
        let corrupted = "## 2026-08-17\n\n### 09:27 · Apple Watch\na twin delivery from the wrist\n\n"
            + nulls
            + "\n\n### 09:27 · Apple Watch\na twin delivery from the wrist\n\n### 08:49 · iPhone\nEarlier thought.\n"
        try corrupted.write(to: store.inboxURL, atomically: true, encoding: .utf8)

        let inbox = try store.loadInbox()
        let texts = inbox.allEntries().map { $0.entry.text }
        XCTAssertEqual(texts.filter { $0 == "a twin delivery from the wrist" }.count, 1)
        XCTAssertTrue(texts.contains("Earlier thought."))
        XCTAssertFalse(texts.contains { $0.contains("\u{0000}") })

        // The live file is rewritten clean, and the repair survives a reload.
        let onDisk = try XCTUnwrap(try store.readString(store.inboxURL))
        XCTAssertFalse(onDisk.contains("\u{0000}"))
        XCTAssertEqual(try store.loadInbox(), inbox)
    }

    func testCollapseExactDuplicatesKeepsDistinctEntries() {
        var inbox = Inbox()
        inbox.prepend(text: "same minute, different thought", at: date("2026-08-17 09:27"), device: "Apple Watch")
        inbox.prepend(text: "twin", at: date("2026-08-17 09:27"), device: "Apple Watch")
        inbox.prepend(text: "twin", at: date("2026-08-17 09:27"), device: "Apple Watch")
        inbox.prepend(text: "twin", at: date("2026-08-17 09:27"), device: "iPhone")
        XCTAssertEqual(inbox.collapseExactDuplicates(), 1)
        XCTAssertEqual(inbox.allEntries().count, 3)
    }

    func testDrainClearsNullOnlySpoolInsteadOfCountingIt() throws {
        let store = try makeTempStore()
        var inbox = try store.loadInbox()
        try store.writeStringInPlace(String(repeating: "\u{0000}", count: 64), to: store.spoolURL)
        XCTAssertEqual(try store.drainSpool(into: &inbox), 0)
        let after = ((try store.readString(store.spoolURL)) ?? nil) ?? ""
        XCTAssertEqual(after, "")
        // And the waiting-line math sees nothing, not a phantom capture.
        XCTAssertEqual(Spool.status("\u{0000}\u{0000}", fallbackDate: date("2026-08-17 09:00")), .empty)
    }

    // MARK: Damaged headers (incident 2026-09-03)

    func testDamagedDayHeaderStillFilesItsEntries() {
        // The live file on 2026-09-03: a backtick glued to the day header.
        // Strict parsing demoted both Mac entries to preamble, which the phone
        // never renders. The reader must recognise the day and report the fix.
        let damaged = "## 2026-09-03`\n### 09:36 · MacBook M4\ndeploy check 0930\n\n### 09:35 · MacBook M4\ndeploy check 0930\n\n## 2026-09-01\n### 08:05 · iPhone\nhttps://example.com\n"
        let report = Inbox.parseReporting(damaged)
        XCTAssertEqual(report.repairs, ["repaired the day header for 2026-09-03"])
        XCTAssertEqual(report.inbox.preamble, "", "nothing may be hidden as preamble")
        XCTAssertEqual(report.inbox.days.map(\.day), ["2026-09-03", "2026-09-01"])
        XCTAssertEqual(report.inbox.days[0].entries.count, 2)
        XCTAssertEqual(report.inbox.days[0].freeText, "", "punctuation-only junk is dropped")
        // Serializing writes the canonical header, and the healed file parses clean.
        let healed = report.inbox.serialized()
        XCTAssertTrue(healed.hasPrefix("## 2026-09-03\n"))
        XCTAssertEqual(Inbox.parseReporting(healed).repairs, [])
        XCTAssertEqual(Inbox.parse(healed), report.inbox)
    }

    func testDayHeaderJunkWithWordsIsKeptAsFreeText() {
        let report = Inbox.parseReporting("## 2026-09-03 standup notes\n### 09:00\nx\n")
        XCTAssertEqual(report.inbox.days[0].day, "2026-09-03")
        XCTAssertEqual(report.inbox.days[0].freeText, "standup notes")
        XCTAssertEqual(report.repairs.count, 1)
    }

    func testDayHeaderKeyRequiresARealDate() {
        XCTAssertNil(LedgeFormat.dayHeaderKey("## Ideas"))
        XCTAssertNil(LedgeFormat.dayHeaderKey("## 2026-13-45"))
        XCTAssertNil(LedgeFormat.dayHeaderKey("### 2026-09-03"))
        XCTAssertEqual(LedgeFormat.dayHeaderKey("## 2026-09-03")?.day, "2026-09-03")
        XCTAssertEqual(LedgeFormat.dayHeaderKey("## 2026-09-03`")?.junk, "`")
        // Captured text is defused by the same lenient rule the reader uses.
        XCTAssertTrue(LedgeFormat.escapingStructure("## 2026-09-03`").hasPrefix("\u{200B}"))
    }

    func testDuplicateDaySectionsAreMerged() {
        // A phone writing while the Mac's header was damaged creates a second
        // section for the same day. Both must survive as one day, newest first.
        let text = "## 2026-09-03\n### 12:30 · iPhone\nsync probe\n\n## 2026-09-03`\n### 09:36 · MacBook M4\ndeploy check\n\n## 2026-09-01\n### 08:05 · iPhone\nolder\n"
        let report = Inbox.parseReporting(text)
        XCTAssertEqual(report.inbox.days.map(\.day), ["2026-09-03", "2026-09-01"])
        let today = report.inbox.days[0].entries
        XCTAssertEqual(today.map(\.text), ["sync probe", "deploy check"])
        XCTAssertTrue(report.repairs.contains("merged a second section for 2026-09-03"))
        XCTAssertTrue(report.repairs.contains("repaired the day header for 2026-09-03"))
    }

    func testLoadInboxHealsDamagedHeaderOnDisk() throws {
        let store = try makeTempStore()
        try store.writeString("## 2026-09-03`\n### 09:36 · MacBook M4\ndeploy check 0930\n", to: store.inboxURL)
        let inbox = try store.loadInbox()
        XCTAssertEqual(store.lastLoadRepairs, ["repaired the day header for 2026-09-03"])
        XCTAssertEqual(inbox.allEntries().count, 1)
        let onDisk = try XCTUnwrap(try store.readString(store.inboxURL))
        XCTAssertTrue(onDisk.hasPrefix("## 2026-09-03\n"), "the live file is rewritten in canonical form")
        _ = try store.loadInbox()
        XCTAssertEqual(store.lastLoadRepairs, [], "a healed file needs no further repair")
    }

    // MARK: Sync health (heartbeats)

    func testHeartbeatRoundTripAndPeerLine() throws {
        let store = try makeTempStore()
        let now = date("2026-09-03 12:00")
        try store.writeHeartbeat(device: "MacBook M4", version: "0.4.2", platform: "macOS", now: date("2026-09-03 03:00"))
        try store.writeHeartbeat(device: "iPhone", version: "0.4.2", platform: "iOS", now: now)
        let beats = store.readHeartbeats()
        XCTAssertEqual(beats.map(\.device), ["iPhone", "MacBook M4"], "newest first")
        XCTAssertEqual(store.heartbeatURL(for: "MacBook M4").lastPathComponent, "heartbeat-macbook-m4.json")
        // The Mac was last seen 9 hours ago: over the 6 hour threshold, so the phone says so.
        XCTAssertEqual(LedgeStore.peerLine(from: beats, selfDevice: "iPhone", now: now), "last seen from MacBook M4: 9 hours ago")
        // From the Mac's point of view the phone was seen just now: silent.
        XCTAssertNil(LedgeStore.peerLine(from: beats, selfDevice: "MacBook M4", now: now))
        // A lone device has no peer to report on.
        XCTAssertNil(LedgeStore.peerLine(from: beats.filter { $0.device == "iPhone" }, selfDevice: "iPhone", now: now))
        // Rewriting the same device replaces, never accumulates.
        try store.writeHeartbeat(device: "iPhone", version: "0.4.2", platform: "iOS", now: now.addingTimeInterval(60))
        XCTAssertEqual(store.readHeartbeats().count, 2)
    }

    func testHeartbeatCarriesTheInboxDigest() throws {
        let store = try makeTempStore()
        try store.writeHeartbeat(device: "iPhone", version: "0.4.2", platform: "iOS")
        let beat = try XCTUnwrap(store.readHeartbeats().first)
        let expected = try XCTUnwrap(store.inboxDigest())
        XCTAssertEqual(beat.inboxDigest, expected)
        XCTAssertEqual(expected.count, 16, "16 hex characters, the same prefix deploy.sh takes from shasum -a 256")
        // The digest is over the raw bytes on disk, so it moves when the file moves.
        var inbox = try store.loadInbox()
        inbox.prepend(text: "changed", at: date("2026-09-03 13:00"), device: "iPhone")
        try store.saveInbox(inbox)
        XCTAssertNotEqual(store.inboxDigest(), expected)
        // And it decodes without the field, for heartbeats written by 0.4.2 builds before it existed.
        let legacy = Data("{\"at\":\"2026-09-03T07:00:00Z\",\"device\":\"Mac\",\"platform\":\"macOS\",\"version\":\"0.4.2\"}".utf8)
        try FileManager.default.createDirectory(at: store.stateURL, withIntermediateDirectories: true)
        try legacy.write(to: store.heartbeatURL(for: "Mac"))
        XCTAssertEqual(store.readHeartbeats().count, 2)
    }

    func testRoughAge() {
        XCTAssertEqual(LedgeFormat.roughAge(5), "just now")
        XCTAssertEqual(LedgeFormat.roughAge(90), "1 minute ago")
        XCTAssertEqual(LedgeFormat.roughAge(4 * 3600 + 10), "4 hours ago")
        XCTAssertEqual(LedgeFormat.roughAge(3 * 86400), "3 days ago")
    }

    func testProbeWriteAccessSucceedsOnWritableFolder() throws {
        let store = try makeTempStore()
        XCTAssertNoThrow(try store.probeWriteAccess())
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.stateURL.path).filter { $0.hasPrefix(".probe-") }
        XCTAssertEqual(leftovers, [], "the probe cleans up after itself")
    }

    func testWellFormedFileReportsNoRepairs() {
        var inbox = Inbox()
        inbox.prepend(text: "a", at: date("2026-09-03 09:00"), device: "iPhone")
        inbox.prepend(text: "b", at: date("2026-09-02 09:00"), device: "iPhone")
        XCTAssertEqual(Inbox.parseReporting(inbox.serialized()).repairs, [])
    }
}

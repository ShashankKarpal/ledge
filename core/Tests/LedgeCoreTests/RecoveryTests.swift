// Recovery report tests. The report is the one artefact designed to be
// pasted somewhere, so the first test plants a phrase in every place capture
// text can live and asserts none of them survive into the text.
// Built by Claude (Anthropic).

import XCTest
@testable import LedgeCore

final class RecoveryTests: XCTestCase {

    func date(_ stamp: String) -> Date {
        guard let d = LedgeFormat.spoolFormatter.date(from: stamp) else {
            fatalError("bad test stamp " + stamp)
        }
        return d
    }

    func makeTempStore() throws -> LedgeStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgeRecoveryTests-" + UUID().uuidString, isDirectory: true)
        let store = LedgeStore(root: root)
        try store.bootstrap(now: date("2026-09-01 09:00"))
        return store
    }

    func testDiagnosticReportHoldsNoCaptureText() throws {
        let store = try makeTempStore()
        let now = date("2026-09-14 12:00")

        // 1. Inbox text.
        var inbox = try store.loadInbox()
        inbox.prepend(text: "INBOX-PHRASE-ALPHA the dentist at four", at: date("2026-09-14 11:00"), device: "MacBook M4")
        try store.saveInbox(inbox)

        // 2. Spool text (a capture no device has folded yet).
        try store.appendSpoolLine(Spool.line(for: "SPOOL-PHRASE-BRAVO call the bank", at: date("2026-09-14 11:30"), device: "iPhone", id: "abc"))

        // 3. Capture log text, unconfirmed, old enough to count as unaccounted.
        let logURL = store.root.appendingPathComponent("capture-log-test.jsonl")
        let log = CaptureLog(url: logURL)
        _ = try log.record(text: "LOG-PHRASE-CHARLIE buy oat milk", device: "MacBook M4", intent: "inbox", at: date("2026-09-14 10:00"))

        // 4. Editor recovery journal text.
        let journal = store.root.appendingPathComponent("editor-recovery-test.md")
        try "JOURNAL-PHRASE-DELTA unsaved thought".write(to: journal, atomically: true, encoding: .utf8)

        // 5. Heartbeats and an incident, which are content-free by design.
        try store.writeHeartbeat(device: "MacBook M4", version: "0.5.1", platform: "macOS", now: now.addingTimeInterval(-60))
        try store.writeHeartbeat(device: "iPhone", version: "0.5.1", platform: "iOS", now: now.addingTimeInterval(-3600))
        store.noteIncident(SyncIncident(kind: .disagreement, observer: "iPhone", startedAt: now.addingTimeInterval(-7200), endedAt: now.addingTimeInterval(-6900), peer: "MacBook M4", version: "0.5.1", secondsAfterInstall: 12))

        let report = RecoveryReport.gather(RecoveryReport.Sources(
            store: store,
            captureLog: log,
            editorJournalURL: journal,
            backups: nil,
            selfDevice: "MacBook M4",
            appVersion: "0.5.1",
            platform: "macOS",
            syncHealthLine: nil
        ), now: now)
        let text = report.diagnosticText()

        for phrase in ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "dentist", "bank", "oat milk", "unsaved thought"] {
            XCTAssertFalse(text.contains(phrase), "capture text leaked into the report: \(phrase)\n\(text)")
        }

        // What it MUST say, so a content-free report is not an empty one.
        XCTAssertEqual(report.spool.count, 1)
        XCTAssertTrue(text.contains("spool (capture/drop.md): 1 waiting"))
        XCTAssertEqual(report.unaccounted.count, 1)
        XCTAssertEqual(report.unaccounted.first?.device, "MacBook M4")
        XCTAssertTrue(text.contains("unaccounted captures: 1"))
        XCTAssertTrue(text.contains("2026-09-14 10:00 from MacBook M4"))
        XCTAssertTrue(text.contains("editor recovery journal: present, 36 bytes"))
        XCTAssertEqual(report.heartbeats.count, 2)
        XCTAssertTrue(text.contains("heartbeat MacBook M4 (this device): 1 minute ago, macOS 0.5.1, same bytes"))
        XCTAssertTrue(text.contains("heartbeat iPhone: 1 hour ago, iOS 0.5.1, same bytes"))
        XCTAssertEqual(report.incidentSummary30d.count, 1)
        XCTAssertTrue(text.contains("count: 1, total 5 minutes"))
        XCTAssertTrue(text.contains("disagreement seen by iPhone vs MacBook M4"))
        XCTAssertTrue(text.contains("backups: none yet"))
        XCTAssertEqual(report.inboxEntries, 2, "onboarding entry plus the planted one")
        XCTAssertNotNil(report.inboxDigest)
        XCTAssertTrue(text.contains("inbox digest: " + report.inboxDigest!))
        XCTAssertFalse(text.contains("/Users/"), "the report must not carry an account path")
    }

    func testReportOnEmptyFolderIsCalm() throws {
        let store = try makeTempStore()
        let now = date("2026-09-14 12:00")
        let report = RecoveryReport.gather(RecoveryReport.Sources(
            store: store, selfDevice: "MacBook M4", appVersion: "dev", platform: "macOS"
        ), now: now)
        XCTAssertTrue(report.folderReachable)
        XCTAssertTrue(report.inboxExists)
        XCTAssertEqual(report.spool.count, 0)
        XCTAssertEqual(report.unaccounted, [])
        XCTAssertEqual(report.conflictVersions, 0)
        XCTAssertEqual(report.incidentSummary30d.count, 0)
        XCTAssertNil(report.editorJournalBytes)
        let text = report.diagnosticText()
        XCTAssertTrue(text.contains("unaccounted captures: 0"))
        XCTAssertTrue(text.contains("editor recovery journal: none"))
        XCTAssertTrue(text.contains("heartbeats: none"))
        XCTAssertTrue(text.contains("health line: healthy (no line)"))
    }

    func testGatheringNeverWritesIntoTheFolder() throws {
        // Observational means observational: a report must not change a byte
        // of the synced folder, or it becomes load on the transport it is
        // describing (the 0.4.4 write-probe lesson).
        let store = try makeTempStore()
        try store.appendSpoolLine(Spool.line(for: "x", at: date("2026-09-14 11:30"), device: "iPhone", id: "id1"))
        let before = try snapshot(of: store.root)
        _ = RecoveryReport.gather(RecoveryReport.Sources(
            store: store, selfDevice: "MacBook M4", appVersion: "dev", platform: "macOS"
        ), now: date("2026-09-14 12:00"))
        let after = try snapshot(of: store.root)
        XCTAssertEqual(before, after)
    }

    func testAbbreviateHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(RecoveryReport.abbreviateHome(home + "/Documents/Ledge"), "~/Documents/Ledge")
        XCTAssertEqual(RecoveryReport.abbreviateHome("/Volumes/Other/Ledge"), "/Volumes/Other/Ledge")
    }

    /// Every file under root with its size and modification date.
    private func snapshot(of root: URL) throws -> [String: String] {
        let fm = FileManager.default
        var out: [String: String] = [:]
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return out }
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            if values.isDirectory == true { continue }
            out[url.path] = "\(values.fileSize ?? -1)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        return out
    }
}

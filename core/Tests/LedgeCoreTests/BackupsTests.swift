// Local backups tests: change-driven, verified, bounded, newest never deleted.
// Built by Claude (Anthropic).

import XCTest
@testable import LedgeCore

final class BackupsTests: XCTestCase {

    func makeRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgeBackupsTests-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func utc(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    func testSnapshotIsChangeDrivenAndVerified() throws {
        let root = makeRoot()
        let backups = LocalBackups(root: root.appendingPathComponent("backups"))
        let source = root.appendingPathComponent("inbox.md")
        try "## 2026-09-14\n### 09:00 · Mac\nfirst\n".write(to: source, atomically: true, encoding: .utf8)

        let first = try backups.snapshot(source, name: "inbox", now: utc("2026-09-14T09:00:00Z"))
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.digest, LedgeStore.digest(of: try Data(contentsOf: source)))
        XCTAssertTrue(first!.url.lastPathComponent.hasPrefix("inbox-20260914T090000Z-"))
        XCTAssertEqual(try Data(contentsOf: first!.url), try Data(contentsOf: source), "the copy is byte-identical")

        // Same bytes again: nothing stored.
        XCTAssertNil(try backups.snapshot(source, name: "inbox", now: utc("2026-09-14T09:05:00Z")))
        XCTAssertEqual(backups.entries().count, 1)

        // Changed bytes: a second file, and the first still exists.
        try "## 2026-09-14\n### 09:10 · Mac\nsecond\n### 09:00 · Mac\nfirst\n".write(to: source, atomically: true, encoding: .utf8)
        let second = try backups.snapshot(source, name: "inbox", now: utc("2026-09-14T09:10:00Z"))
        XCTAssertNotNil(second)
        let all = backups.entries()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first!.url.path))
        XCTAssertEqual(backups.newest(named: "inbox")?.digest, second?.digest)

        // No temp files left behind, manifest has two lines.
        let files = try FileManager.default.contentsOfDirectory(atPath: backups.root.path)
        XCTAssertFalse(files.contains { $0.hasSuffix(".tmp") })
        let manifest = try String(contentsOf: backups.manifestURL, encoding: .utf8)
        XCTAssertEqual(manifest.split(separator: "\n").count, 2)

        let status = backups.status()
        XCTAssertEqual(status.count, 2)
        XCTAssertEqual(status.newest, utc("2026-09-14T09:10:00Z"))
        XCTAssertEqual(status.bytes, all.reduce(0) { $0 + $1.bytes })
    }

    func testUnreadableSourceThrowsAndStoresNothing() throws {
        let root = makeRoot()
        let backups = LocalBackups(root: root.appendingPathComponent("backups"))
        XCTAssertThrowsError(try backups.snapshot(root.appendingPathComponent("missing.md"), name: "inbox"))
        XCTAssertEqual(backups.entries().count, 0)
    }

    func testFileNameRoundTripWithHyphenatedName() {
        let at = utc("2026-08-03T23:59:59Z")
        let name = LocalBackups.fileName(name: "attic-2026-08", at: at, digest: "0123456789abcdef", ext: "md")
        XCTAssertEqual(name, "attic-2026-08-20260803T235959Z-0123456789abcdef.md")
        let parsed = LocalBackups.parse(fileName: name)
        XCTAssertEqual(parsed?.name, "attic-2026-08")
        XCTAssertEqual(parsed?.at, at)
        XCTAssertEqual(parsed?.digest, "0123456789abcdef")
        XCTAssertNil(LocalBackups.parse(fileName: "manifest.jsonl"))
        XCTAssertNil(LocalBackups.parse(fileName: "inbox-garbage-0123456789abcdef.md"))
    }

    /// 500 synthetic snapshots spread over 200 days: the tiers hold, the
    /// newest survives, and the count is bounded.
    func testPruneKeepsTiersAndNeverTheNewest() throws {
        let root = makeRoot()
        let policy = LocalBackups.Policy(keepAllFor: 48 * 3600, dailyFor: 30 * 86400, weeklyFor: 182 * 86400, maxTotalBytes: 10_000_000)
        let backups = LocalBackups(root: root.appendingPathComponent("backups"), policy: policy)
        try FileManager.default.createDirectory(at: backups.root, withIntermediateDirectories: true)
        let now = utc("2026-09-14T12:00:00Z")

        // Plant 500 files: one every 9.6 hours going back 200 days.
        var planted: [Date] = []
        for i in 0..<500 {
            let at = now.addingTimeInterval(-Double(i) * 9.6 * 3600)
            planted.append(at)
            let digest = String(format: "%016x", i + 1)
            let url = backups.root.appendingPathComponent(LocalBackups.fileName(name: "inbox", at: at, digest: digest, ext: "md"))
            try "snapshot \(i)\n".write(to: url, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(backups.entries().count, 500)

        let removed = backups.prune(now: now)
        let left = backups.entries()
        XCTAssertEqual(removed + left.count, 500)

        // Newest survives.
        XCTAssertEqual(left.last?.at, planted[0])

        // Everything younger than 48 h survives: 48 h / 9.6 h = 5 files plus the one at 0.
        let young = planted.filter { now.timeIntervalSince($0) <= 48 * 3600 }
        for d in young {
            XCTAssertTrue(left.contains { $0.at == d }, "young snapshot at \(d) must survive")
        }

        var utcCal = Calendar(identifier: .iso8601)
        utcCal.timeZone = TimeZone(identifier: "UTC")!

        // 48 h to 30 d: at most one per UTC day, and each day that had a
        // snapshot still has one (its newest).
        let daily = left.filter { let a = now.timeIntervalSince($0.at); return a > 48 * 3600 && a <= 30 * 86400 }
        let dayKeys = daily.map { utcCal.dateComponents([.year, .month, .day], from: $0.at) }
        XCTAssertEqual(Set(dayKeys.map { "\($0.year!)-\($0.month!)-\($0.day!)" }).count, dayKeys.count, "one per day")
        let plantedDailyDays = Set(planted.filter { let a = now.timeIntervalSince($0); return a > 48 * 3600 && a <= 30 * 86400 }
            .map { c -> String in let k = utcCal.dateComponents([.year, .month, .day], from: c); return "\(k.year!)-\(k.month!)-\(k.day!)" })
        XCTAssertEqual(Set(dayKeys.map { "\($0.year!)-\($0.month!)-\($0.day!)" }), plantedDailyDays, "every day that had a snapshot keeps one")

        // 30 d to 182 d: at most one per ISO week.
        let weekly = left.filter { let a = now.timeIntervalSince($0.at); return a > 30 * 86400 && a <= 182 * 86400 }
        let weekKeys = weekly.map { c -> String in let k = utcCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: c.at); return "\(k.yearForWeekOfYear!)-\(k.weekOfYear!)" }
        XCTAssertEqual(Set(weekKeys).count, weekKeys.count, "one per week")
        XCTAssertGreaterThan(weekly.count, 15)

        // Older than 182 d: gone.
        XCTAssertEqual(left.filter { now.timeIntervalSince($0.at) > 182 * 86400 }.count, 0)

        // Bounded: about 6 young + 28 daily + 22 weekly.
        XCTAssertLessThan(left.count, 70)
        XCTAssertGreaterThan(left.count, 40)

        // A second prune is a no-op.
        XCTAssertEqual(backups.prune(now: now), 0)
    }

    func testByteCapEvictsOldestFirstButNeverTheNewest() throws {
        let root = makeRoot()
        let policy = LocalBackups.Policy(keepAllFor: 365 * 86400, dailyFor: 400 * 86400, weeklyFor: 500 * 86400, maxTotalBytes: 2500)
        let backups = LocalBackups(root: root.appendingPathComponent("backups"), policy: policy)
        try FileManager.default.createDirectory(at: backups.root, withIntermediateDirectories: true)
        let now = utc("2026-09-14T12:00:00Z")
        for i in 0..<5 {
            let at = now.addingTimeInterval(-Double(i) * 3600)
            let url = backups.root.appendingPathComponent(LocalBackups.fileName(name: "inbox", at: at, digest: String(format: "%016x", i + 1), ext: "md"))
            try String(repeating: "x", count: 1000).write(to: url, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(backups.prune(now: now), 3, "5000 bytes over a 2500 cap removes the three oldest")
        let left = backups.entries()
        XCTAssertEqual(left.count, 2)
        XCTAssertEqual(left.last?.at, now)
        XCTAssertEqual(left.first?.at, now.addingTimeInterval(-3600))
    }

    func testNewestSurvivesEvenWhenExpired() throws {
        let root = makeRoot()
        let backups = LocalBackups(root: root.appendingPathComponent("backups"))
        try FileManager.default.createDirectory(at: backups.root, withIntermediateDirectories: true)
        let now = utc("2026-09-14T12:00:00Z")
        let old = now.addingTimeInterval(-400 * 86400)
        let url = backups.root.appendingPathComponent(LocalBackups.fileName(name: "inbox", at: old, digest: "0123456789abcdef", ext: "md"))
        try "ancient\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(backups.prune(now: now), 0)
        XCTAssertEqual(backups.entries().count, 1)
    }
}

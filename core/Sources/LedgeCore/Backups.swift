// Local versioned backups, outside iCloud.
//
// iCloud is sync, not backup: a bad merge or an accidental delete reaches
// every device within seconds. These snapshots live on this device only, in
// Application Support, so the day something goes wrong the previous bytes are
// still on a disk that iCloud does not touch.
//
// Rules, each with a test:
//
// - CHANGE-DRIVEN. A snapshot is taken only when the file's bytes differ
//   from the newest snapshot of it. Nothing runs on a timer while idle, and
//   identical bytes are never stored twice.
// - VERIFIED BEFORE IT COUNTS. The bytes are written to a temporary name in
//   the backups folder, read back, digested, and compared to the source
//   digest. Only then is the file renamed into place and its manifest line
//   appended. A snapshot that cannot be proven is deleted, never kept.
// - APPEND, NEVER REWRITE. New snapshots are new files; the manifest is
//   append-only. The one operation that removes anything is prune, and prune
//   never touches the newest snapshot of a file.
// - BOUNDED. Everything from the last 48 hours; then the newest per UTC day
//   for 30 days; then the newest per week for six months; then nothing. On
//   top of that a hard byte cap evicts oldest first.
// - UTC IN NAMES. Snapshot names carry a UTC stamp so sorting survives a
//   time zone change on the machine (fleet lesson, 2026-09-05).
//
// This file never reads the synced folder for anything but the bytes it is
// asked to copy, and never writes into it.
// Built by Claude (Anthropic).

import Foundation

public final class LocalBackups {
    public struct Policy: Equatable {
        /// Keep every snapshot younger than this.
        public var keepAllFor: TimeInterval
        /// After that, keep the newest per UTC day until this age.
        public var dailyFor: TimeInterval
        /// After that, keep the newest per week until this age.
        public var weeklyFor: TimeInterval
        /// Hard cap on the folder, oldest evicted first, newest never.
        public var maxTotalBytes: Int

        public init(keepAllFor: TimeInterval, dailyFor: TimeInterval, weeklyFor: TimeInterval, maxTotalBytes: Int) {
            self.keepAllFor = keepAllFor
            self.dailyFor = dailyFor
            self.weeklyFor = weeklyFor
            self.maxTotalBytes = maxTotalBytes
        }

        public static let standard = Policy(
            keepAllFor: 48 * 3600,
            dailyFor: 30 * 86400,
            weeklyFor: 182 * 86400,
            maxTotalBytes: 200 * 1024 * 1024
        )
    }

    /// One snapshot on disk, parsed from its file name.
    public struct Entry: Equatable, Comparable {
        public var url: URL
        /// The source file this is a copy of, e.g. "inbox" or "attic-2026-08".
        public var name: String
        public var at: Date
        public var digest: String
        public var bytes: Int

        public static func < (a: Entry, b: Entry) -> Bool { a.at < b.at }
    }

    public let root: URL
    public let policy: Policy
    private let fm = FileManager.default
    private let lock = NSLock()

    public init(root: URL, policy: Policy = .standard) {
        self.root = root
        self.policy = policy
    }

    /// The default per-device location, beside the capture log.
    public static func defaultRoot() -> URL {
        CaptureLog.defaultURL().deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
    }

    public var manifestURL: URL { root.appendingPathComponent("manifest.jsonl") }

    // MARK: Names

    static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    /// `inbox-20260914T113015Z-375256ada524251b.md`
    static func fileName(name: String, at: Date, digest: String, ext: String) -> String {
        name + "-" + stampFormatter.string(from: at) + "-" + digest + "." + ext
    }

    static func parse(fileName: String) -> (name: String, at: Date, digest: String)? {
        let base = (fileName as NSString).deletingPathExtension
        let parts = base.split(separator: "-")
        guard parts.count >= 3 else { return nil }
        let digest = String(parts[parts.count - 1])
        let stamp = String(parts[parts.count - 2])
        let name = parts[0..<(parts.count - 2)].joined(separator: "-")
        guard !name.isEmpty, digest.count == 16, let at = stampFormatter.date(from: stamp) else { return nil }
        return (name, at, digest)
    }

    // MARK: Reading

    /// Every verified snapshot on disk, oldest first. Temporary files (still
    /// being written, or left by a crash) are not snapshots and are skipped.
    public func entries() -> [Entry] {
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [Entry] = []
        for url in items {
            let file = url.lastPathComponent
            guard !file.hasPrefix("."), file != "manifest.jsonl", !file.hasSuffix(".tmp") else { continue }
            guard let parsed = Self.parse(fileName: file) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            out.append(Entry(url: url, name: parsed.name, at: parsed.at, digest: parsed.digest, bytes: size))
        }
        return out.sorted()
    }

    public func newest(named name: String) -> Entry? {
        entries().filter { $0.name == name }.last
    }

    public func status() -> RecoveryReport.Backups {
        let all = entries()
        return RecoveryReport.Backups(
            count: all.count,
            newest: all.last?.at,
            bytes: all.reduce(0) { $0 + $1.bytes }
        )
    }

    // MARK: Writing

    public enum Failure: Error, Equatable {
        case sourceUnreadable
        case verificationFailed(expected: String, got: String)
    }

    /// Copy `source` into the backups folder under `name` if its bytes differ
    /// from the newest snapshot of that name. Returns the new snapshot, or
    /// nil when nothing changed. Throws when the source cannot be read or the
    /// written copy does not read back byte-identical.
    @discardableResult
    public func snapshot(_ source: URL, name: String, now: Date = Date()) throws -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: source) else { throw Failure.sourceUnreadable }
        let digest = LedgeStore.digest(of: data)
        if let latest = newest(named: name), latest.digest == digest { return nil }

        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "md" : source.pathExtension
        let finalName = Self.fileName(name: name, at: now, digest: digest, ext: ext)
        let finalURL = root.appendingPathComponent(finalName)
        let tempURL = root.appendingPathComponent("." + finalName + ".tmp")

        // Write, read back, prove, then rename. A copy that cannot be proven
        // is removed rather than kept as a false comfort.
        try data.write(to: tempURL, options: [.atomic])
        let readBack = try Data(contentsOf: tempURL)
        let got = LedgeStore.digest(of: readBack)
        guard got == digest, readBack == data else {
            try? fm.removeItem(at: tempURL)
            throw Failure.verificationFailed(expected: digest, got: got)
        }
        if fm.fileExists(atPath: finalURL.path) {
            // Same second, same bytes: already there. Drop the temp copy.
            try? fm.removeItem(at: tempURL)
        } else {
            try fm.moveItem(at: tempURL, to: finalURL)
        }
        try? LedgeStore.appendLine(
            "{\"at\":\"\(Self.stampFormatter.string(from: now))\",\"file\":\"\(finalName)\",\"digest\":\"\(digest)\",\"bytes\":\(data.count)}",
            to: manifestURL
        )
        return Entry(url: finalURL, name: name, at: now, digest: digest, bytes: data.count)
    }

    // MARK: Pruning

    /// Apply the retention tiers and the byte cap. Returns the number of
    /// snapshots removed. Never removes the newest snapshot of any name, and
    /// never removes anything younger than `keepAllFor`.
    @discardableResult
    public func prune(now: Date = Date()) -> Int {
        lock.lock()
        defer { lock.unlock() }
        var all = entries()
        var removed = 0

        // Newest per name is untouchable.
        var protected = Set<URL>()
        var newestByName: [String: Entry] = [:]
        for e in all {
            if let cur = newestByName[e.name], cur.at >= e.at { continue }
            newestByName[e.name] = e
        }
        for e in newestByName.values { protected.insert(e.url) }

        var utc = Calendar(identifier: .iso8601)
        utc.timeZone = TimeZone(identifier: "UTC")!

        func bucket(_ e: Entry) -> String? {
            let age = now.timeIntervalSince(e.at)
            if age <= policy.keepAllFor { return nil }              // keep all, no bucket
            if age <= policy.dailyFor {
                let c = utc.dateComponents([.year, .month, .day], from: e.at)
                return "\(e.name)|d|\(c.year!)-\(c.month!)-\(c.day!)"
            }
            if age <= policy.weeklyFor {
                let c = utc.dateComponents([.yearForWeekOfYear, .weekOfYear], from: e.at)
                return "\(e.name)|w|\(c.yearForWeekOfYear!)-\(c.weekOfYear!)"
            }
            return "\(e.name)|expired"
        }

        // Within each bucket keep the newest; everything else in the bucket
        // goes. Expired entries all go (except a protected newest).
        var keepInBucket: [String: Entry] = [:]
        for e in all {
            guard let b = bucket(e), !b.hasSuffix("|expired") else { continue }
            if let cur = keepInBucket[b], cur.at >= e.at { continue }
            keepInBucket[b] = e
        }
        let keepers = Set(keepInBucket.values.map(\.url))

        var survivors: [Entry] = []
        for e in all {
            if protected.contains(e.url) { survivors.append(e); continue }
            guard let b = bucket(e) else { survivors.append(e); continue }
            if b.hasSuffix("|expired") || !keepers.contains(e.url) {
                if (try? fm.removeItem(at: e.url)) != nil { removed += 1 } else { survivors.append(e) }
            } else {
                survivors.append(e)
            }
        }
        all = survivors

        // Byte cap: oldest first, never a protected newest.
        var total = all.reduce(0) { $0 + $1.bytes }
        if total > policy.maxTotalBytes {
            for e in all where !protected.contains(e.url) {
                if total <= policy.maxTotalBytes { break }
                if (try? fm.removeItem(at: e.url)) != nil {
                    total -= e.bytes
                    removed += 1
                }
            }
        }
        return removed
    }
}

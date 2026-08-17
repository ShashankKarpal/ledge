// LedgeStore: coordinated file IO over the Ledge folder. The folder is the database.
// Built by Claude (Anthropic).
//
// Concurrency contract (added after the 2026-07-24 clobber incident):
// 1. A read never mistakes "not downloaded from iCloud yet" for "empty".
// 2. A save never blindly overwrites bytes that changed since our last read;
//    it merges into the disk state instead. Losing disk content is never OK.
// 3. The spool is truncated by exactly what was folded, never wholesale.

import Foundation

public struct NoteMeta: Identifiable, Equatable {
    public var id: URL { url }
    public let url: URL
    public let title: String
    public let modified: Date
}

public enum LedgeStoreError: Error, Equatable {
    /// The file exists in iCloud but its bytes are not on this device yet
    /// (or exist but could not be read). Callers must not treat this as empty.
    case notDownloaded(URL)
}

public final class LedgeStore {
    public let root: URL
    private let fm = FileManager.default

    /// Modification date of each file at the moment we last successfully read it.
    /// Used to detect writes from other devices or processes before we save.
    private let stampLock = NSLock()
    private var lastReadStamps: [String: Date] = [:]

    public init(root: URL) {
        self.root = root
    }

    // MARK: Locations

    public var inboxURL: URL { root.appendingPathComponent("inbox.md") }
    public var notesURL: URL { root.appendingPathComponent("notes", isDirectory: true) }
    public var atticURL: URL { root.appendingPathComponent("attic", isDirectory: true) }
    public var atticNotesURL: URL { atticURL.appendingPathComponent("notes", isDirectory: true) }
    public var assetsURL: URL { root.appendingPathComponent("assets", isDirectory: true) }
    public var captureURL: URL { root.appendingPathComponent("capture", isDirectory: true) }
    public var spoolURL: URL { captureURL.appendingPathComponent("drop.md") }
    public var stateURL: URL { root.appendingPathComponent(".ledge", isDirectory: true) }
    public var settingsURL: URL { stateURL.appendingPathComponent("settings.json") }
    /// Capture ids already folded into the inbox, one per line, newest last.
    /// Lives in the shared folder so every device drains against the same list.
    public var seenCaptureIDsURL: URL { stateURL.appendingPathComponent("seen-capture-ids.txt") }

    /// Default notes folder: iCloud Drive/Ledge when iCloud Drive exists, else ~/Documents/Ledge.
    /// On iOS the app instead asks the user to pick a folder (document picker + bookmark).
    public static func defaultRoot() -> URL {
        let fm = FileManager.default
        #if os(macOS)
        let home = fm.homeDirectoryForCurrentUser
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if fm.fileExists(atPath: icloud.path) {
            return icloud.appendingPathComponent("Ledge", isDirectory: true)
        }
        return home.appendingPathComponent("Documents/Ledge", isDirectory: true)
        #else
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Ledge", isDirectory: true)
        #endif
    }

    // MARK: Bootstrap

    /// Create the folder structure and seed the inbox with the onboarding entry.
    /// Safe to call on every launch. Never seeds over an iCloud placeholder:
    /// an evicted inbox.md is a real inbox that has not been downloaded yet.
    public func bootstrap(now: Date = Date()) throws {
        for dir in [notesURL, atticNotesURL, assetsURL, captureURL, stateURL] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: inboxURL.path) {
            if hasPlaceholder(inboxURL) {
                try? fm.startDownloadingUbiquitousItem(at: inboxURL)
            } else {
                var inbox = Inbox()
                inbox.prepend(text: Self.seedEntry, at: now)
                try writeString(inbox.serialized(), to: inboxURL)
                recordReadStamp(for: inboxURL)
            }
        }
        if !fm.fileExists(atPath: spoolURL.path), !hasPlaceholder(spoolURL) {
            try writeStringInPlace("", to: spoolURL)
        }
    }

    // The onboarding entry written into a brand new inbox. Affordances differ by
    // platform, so the copy does too: a Mac gets the keyboard shortcuts, a phone
    // or watch gets the taps it actually has. Never teach a gesture the device
    // does not have.
    #if os(macOS)
    static let seedEntry = """
    Welcome to Ledge. This is your inbox: every thought lands here, newest at the top, timestamped for you.

    Try three things, then delete this entry:

    - [ ] press Esc to tuck Ledge away, then Option+Space to summon it again
    - [ ] click this checkbox, then press Cmd+L to see every box still open
    - [ ] type anything below the timestamp that appeared

    No folders, no titles, no filing. Cmd+K finds everything later, and none of it leaves your devices.
    """
    #else
    static let seedEntry = """
    Welcome to Ledge. This is your inbox: every thought lands here, newest at the top, timestamped for you.

    Try three things, then delete this entry:

    - [ ] type a thought into the capture field at the top
    - [ ] tap this checkbox, then open Open loops to see the ones still waiting
    - [ ] add the Ledge widget to your Home Screen for one-tap capture

    No folders, no titles, no filing. Search finds everything later, and none of it leaves your devices.
    """
    #endif

    // MARK: Inbox

    public func loadInbox() throws -> Inbox {
        let raw = try readString(inboxURL) ?? ""
        let clean = LedgeFormat.strippingNulls(raw)
        var inbox = Inbox.parse(clean)
        var dirty = false
        if clean != raw {
            // Null-byte corruption (racing writes, 2026-08-17 incident): keep
            // the damaged bytes recoverable, scrub the nulls, and collapse the
            // exact-duplicate entries the corruption smuggled past fold's
            // dedupe. The rewrite below goes through saveInbox, so it happens
            // under NSFileCoordinator like every other inbox write.
            snapshot(inboxURL)
            inbox.collapseExactDuplicates()
            dirty = true
        }
        if reconcileConflictVersions(into: &inbox) > 0 {
            dirty = true
        }
        if dirty {
            try? saveInbox(inbox)
        }
        return inbox
    }

    /// Fold iCloud conflict versions (the losers of a sync race) back into the
    /// inbox so no device's entries are ever dropped by last-writer-wins.
    /// iCloud keeps the losing side of a conflict as an NSFileVersion on the
    /// device that detects it; without this step those entries silently vanish
    /// from view. Returns the number of entries folded back.
    @discardableResult
    public func reconcileConflictVersions(into inbox: inout Inbox) -> Int {
        #if os(macOS) || os(iOS)
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: inboxURL), !conflicts.isEmpty else { return 0 }
        var folded = 0
        for version in conflicts {
            if let content = try? String(contentsOf: version.url, encoding: .utf8) {
                let lost = Inbox.parse(content)
                for item in lost.allEntries().reversed() {
                    folded += inbox.fold([(date: item.entry.timestamp, text: item.entry.text, device: item.entry.device)])
                }
            }
            version.isResolved = true
        }
        return folded
        #else
        return 0
        #endif
    }

    /// Save the inbox without ever clobbering newer bytes on disk.
    /// If inbox.md changed since our last successful read (another device wrote
    /// it, or we never managed to read it at all), fold our entries into the
    /// current disk state instead of overwriting it. Edits made to an entry on
    /// two devices at once can surface as two entries; that is deliberate,
    /// duplicates are recoverable and lost bytes are not.
    public func saveInbox(_ inbox: Inbox) throws {
        try fm.createDirectory(at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if canImport(Darwin)
        // The stamp check, the merge, and the write all happen inside ONE
        // coordinated write. The old shape (check, merge, then a separately
        // coordinated write) left a window where another coordinated writer
        // (the sync daemon applying an update from another device, or a second
        // drain on this machine) could land bytes between our check and our
        // write and be clobbered; that window is where the 2026-08-17
        // corruption raced.
        var coordinationError: NSError?
        var innerError: Error?
        NSFileCoordinator().coordinate(writingItemAt: inboxURL, options: .forMerging, error: &coordinationError) { actualURL in
            do {
                var outgoing = inbox
                if let diskStamp = self.modificationDate(of: actualURL), diskStamp != self.readStamp(for: self.inboxURL) {
                    self.snapshot(actualURL)
                    guard let diskRaw = try? String(contentsOf: actualURL, encoding: .utf8) else {
                        // Bytes exist on disk but cannot be read right now.
                        // Refusing to write is the only safe move; captures
                        // fall back to the spool or the pending queue and
                        // nothing is lost.
                        throw LedgeStoreError.notDownloaded(self.inboxURL)
                    }
                    var merged = Inbox.parse(LedgeFormat.strippingNulls(diskRaw))
                    for item in outgoing.allEntries().reversed() {
                        _ = merged.fold([(date: item.entry.timestamp, text: item.entry.text, device: item.entry.device)])
                    }
                    outgoing = merged
                }
                try outgoing.serialized().write(to: actualURL, atomically: true, encoding: .utf8)
            } catch {
                innerError = error
            }
        }
        if let error = innerError { throw error }
        if let error = coordinationError { throw error }
        #else
        var outgoing = inbox
        if let diskStamp = modificationDate(of: inboxURL), diskStamp != readStamp(for: inboxURL) {
            guard let diskRaw = ((try? readString(inboxURL)) ?? nil) else {
                throw LedgeStoreError.notDownloaded(inboxURL)
            }
            var merged = Inbox.parse(LedgeFormat.strippingNulls(diskRaw))
            for item in outgoing.allEntries().reversed() {
                _ = merged.fold([(date: item.entry.timestamp, text: item.entry.text, device: item.entry.device)])
            }
            outgoing = merged
        }
        try outgoing.serialized().write(to: inboxURL, atomically: true, encoding: .utf8)
        #endif
        recordReadStamp(for: inboxURL)
    }

    /// Fold pending spool captures into the inbox and truncate the spool.
    /// Returns the number of captures folded. Caller saves the inbox afterwards.
    ///
    /// Captures carrying a delivery id (the watch relay stamps one) are folded
    /// at most once ever: ids already in the seen-ids ledger are dropped, even
    /// across separate drain batches on separate days or devices. This is what
    /// makes the relay's deliver-at-least-once retries safe.
    @discardableResult
    public func drainSpool(into inbox: inout Inbox) throws -> Int {
        guard let raw = try readString(spoolURL), !LedgeFormat.trimEdges(raw).isEmpty else { return 0 }
        let fallback = modificationDate(of: spoolURL) ?? Date()
        let captures = Spool.parse(raw, fallbackDate: fallback)
        guard !captures.isEmpty else {
            // Non-empty bytes that parse to nothing are corruption residue
            // (e.g. a null-byte run); clear them so they never surface as a
            // phantom waiting capture.
            try truncateSpool(consumed: raw)
            return 0
        }
        let seen = seenCaptureIDs()
        let fresh = captures.filter { $0.id == nil || !seen.contains($0.id!) }
        snapshot(inboxURL)
        let added = inbox.fold(fresh.map { (date: $0.date, text: $0.text, device: $0.device) })
        try truncateSpool(consumed: raw)
        // Every id in the batch was consumed (folded, or skipped as a text
        // duplicate of something already present), so all of them are seen.
        recordSeenCaptureIDs(captures.compactMap(\.id))
        return added
    }

    /// The seen-ids ledger, read leniently: a missing or unreadable ledger
    /// just means nothing is deduped by id this round, and fold's
    /// day+minute+text dedupe still stands behind it.
    func seenCaptureIDs() -> Set<String> {
        guard let raw = ((try? readString(seenCaptureIDsURL)) ?? nil) else { return [] }
        return Set(raw.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// Append ids to the ledger, capped to the newest 500. Best effort: a
    /// failed write degrades to text dedupe, it never blocks a drain.
    func recordSeenCaptureIDs(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let existing = (((try? readString(seenCaptureIDsURL)) ?? nil) ?? "")
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var combined = existing
        let known = Set(existing)
        for id in ids where !known.contains(id) {
            combined.append(id)
        }
        let capped = combined.suffix(500).joined(separator: "\n") + "\n"
        try? writeString(capped, to: seenCaptureIDsURL)
    }

    /// Clear exactly the spool content that was folded. Captures appended while
    /// we were folding stay in place for the next drain instead of being wiped.
    /// Internal for tests.
    func truncateSpool(consumed: String) throws {
        let current = ((try? readString(spoolURL)) ?? nil) ?? consumed
        if current == consumed {
            try writeStringInPlace("", to: spoolURL)
        } else if current.hasPrefix(consumed) {
            try writeStringInPlace(String(current.dropFirst(consumed.count)), to: spoolURL)
        }
        // Anything else means the spool was rewritten underneath us: leave it
        // alone. Fold's day+minute+text dedupe makes the next drain harmless.
    }

    // MARK: Aging (the Attic)

    /// Move inbox days older than `olderThanDays` into attic/yyyy-MM.md, verbatim.
    /// Returns the number of entries moved. Caller saves the inbox afterwards.
    @discardableResult
    public func age(_ inbox: inout Inbox, olderThanDays: Int, now: Date = Date()) throws -> Int {
        guard olderThanDays > 0 else { return 0 }
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -olderThanDays, to: calendar.startOfDay(for: now)) else {
            return 0
        }
        var kept: [DaySection] = []
        var aged: [DaySection] = []
        for day in inbox.days {
            if let date = day.date, date < cutoff {
                aged.append(day)
            } else {
                kept.append(day)
            }
        }
        guard !aged.isEmpty else { return 0 }
        snapshot(inboxURL)
        var moved = 0
        for day in aged {
            let month = String(day.day.prefix(7))
            let url = atticURL.appendingPathComponent(month + ".md")
            let chunk = Inbox(days: [day]).serialized()
            let existing = (try readString(url)) ?? ""
            let combined = existing.isEmpty ? chunk : existing + "\n" + chunk
            try writeString(combined, to: url)
            moved += day.entries.count
        }
        inbox.days = kept
        return moved
    }

    // MARK: Notes

    public func noteURLs() throws -> [URL] {
        guard fm.fileExists(atPath: notesURL.path) else { return [] }
        return try fm.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "md" }
    }

    public func listNotes() throws -> [NoteMeta] {
        try noteURLs()
            .map { url in
                let content = ((try? readString(url)) ?? nil) ?? ""
                return NoteMeta(
                    url: url,
                    title: Self.title(of: content, fallback: url.deletingPathExtension().lastPathComponent),
                    modified: modificationDate(of: url) ?? .distantPast
                )
            }
            .sorted { $0.modified > $1.modified }
    }

    public func createNote(title: String, now: Date = Date()) throws -> URL {
        let day = LedgeFormat.dayFormatter.string(from: now)
        let base = day + "-" + LedgeFormat.slug(title)
        var url = notesURL.appendingPathComponent(base + ".md")
        var counter = 2
        while fm.fileExists(atPath: url.path) {
            url = notesURL.appendingPathComponent(base + "-\(counter).md")
            counter += 1
        }
        try writeString("# " + title + "\n\n", to: url)
        recordReadStamp(for: url)
        return url
    }

    /// Save a note (or any Ledge markdown file) without clobbering newer bytes.
    /// If the file changed on disk since our last read of it, the disk version
    /// is preserved in attic/notes with a timestamp suffix before ours is
    /// written. Archive, never silently overwrite.
    public func saveNote(_ text: String, to url: URL, now: Date = Date()) throws {
        if let diskStamp = modificationDate(of: url), diskStamp != readStamp(for: url) {
            snapshot(url)
            let minute = LedgeFormat.timeFormatter.string(from: now).replacingOccurrences(of: ":", with: "")
            let stamp = LedgeFormat.dayFormatter.string(from: now) + "-" + minute
            let base = url.deletingPathExtension().lastPathComponent
            let keep = atticNotesURL.appendingPathComponent(base + "-" + stamp + ".md")
            try fm.createDirectory(at: atticNotesURL, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: keep.path) {
                try? fm.copyItem(at: url, to: keep)
            }
        }
        try writeString(text, to: url)
        recordReadStamp(for: url)
    }

    /// Archive, never delete: move a note into attic/notes/.
    public func archiveNote(at url: URL) throws {
        let destination = atticNotesURL.appendingPathComponent(url.lastPathComponent)
        try fm.createDirectory(at: atticNotesURL, withIntermediateDirectories: true)
        try fm.moveItem(at: url, to: destination)
    }

    public static func title(of content: String, fallback: String) -> String {
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            return trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        }
        return fallback
    }

    // MARK: Attic reading (for search)

    public func atticMonthURLs() throws -> [URL] {
        guard fm.fileExists(atPath: atticURL.path) else { return [] }
        return try fm.contentsOfDirectory(at: atticURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "md" }
    }

    // MARK: iCloud materialization

    /// The hidden placeholder iCloud leaves in place of an evicted file.
    private func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
    }

    private func hasPlaceholder(_ url: URL) -> Bool {
        fm.fileExists(atPath: placeholderURL(for: url).path)
    }

    /// Make sure an iCloud file's bytes are local before a read. When only the
    /// placeholder exists, ask iCloud for the download and wait briefly; if the
    /// bytes never arrive, throw rather than let callers mistake "not
    /// downloaded" for "does not exist".
    private func materialize(_ url: URL, timeout: TimeInterval = 4.0) throws {
        if fm.fileExists(atPath: url.path) {
            // Nudge the sync engine to look for a newer version, then wait
            // briefly if one is on the way. No-op for non-iCloud files.
            try? fm.startDownloadingUbiquitousItem(at: url)
            awaitFreshness(url, timeout: 1.5)
            return
        }
        guard hasPlaceholder(url) else { return }
        do {
            try fm.startDownloadingUbiquitousItem(at: url)
        } catch {
            throw LedgeStoreError.notDownloaded(url)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if fm.fileExists(atPath: url.path) { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw LedgeStoreError.notDownloaded(url)
    }

    /// When iCloud says a newer version of an existing file is on its way,
    /// nudge the download and give it a moment. Shrinks the stale-read window
    /// that turns into cloud conflicts. Best effort, never throws: the merge
    /// guard and conflict reconciliation cover whatever this misses.
    private func awaitFreshness(_ url: URL, timeout: TimeInterval) {
        func status() -> URLUbiquitousItemDownloadingStatus? {
            try? URL(fileURLWithPath: url.path)
                .resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus
        }
        guard let initial = status(), initial != .current else { return }
        try? fm.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let s = status(), s == .current { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    // MARK: Read stamps

    private func recordReadStamp(for url: URL) {
        let stamp = modificationDate(of: url)
        stampLock.lock()
        defer { stampLock.unlock() }
        if let stamp {
            lastReadStamps[url.path] = stamp
        } else {
            lastReadStamps.removeValue(forKey: url.path)
        }
    }

    private func readStamp(for url: URL) -> Date? {
        stampLock.lock()
        defer { stampLock.unlock() }
        return lastReadStamps[url.path]
    }

    // MARK: Coordinated IO

    /// Returns nil only when the file truly does not exist (no placeholder).
    /// Throws LedgeStoreError.notDownloaded when bytes exist but are not local.
    public func readString(_ url: URL) throws -> String? {
        try materialize(url)
        guard fm.fileExists(atPath: url.path) else { return nil }
        #if canImport(Darwin)
        var coordinationError: NSError?
        var readError: Error?
        var result: String?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { actualURL in
            do {
                result = try String(contentsOf: actualURL, encoding: .utf8)
            } catch {
                readError = error
            }
        }
        if let error = readError { throw error }
        if let error = coordinationError { throw error }
        recordReadStamp(for: url)
        return result
        #else
        let result = try String(contentsOf: url, encoding: .utf8)
        recordReadStamp(for: url)
        return result
        #endif
    }

    public func writeString(_ string: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if canImport(Darwin)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { actualURL in
            do {
                try string.write(to: actualURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }
        if let error = writeError { throw error }
        if let error = coordinationError { throw error }
        #else
        try string.write(to: url, atomically: true, encoding: .utf8)
        #endif
    }

    /// Write preserving the file's on-disk identity. Out-of-process bookmarks
    /// (like the Shortcuts "Append to Text File" action pointing at the spool)
    /// survive only if the file is never atomically replaced, so this truncates
    /// and rewrites the existing file in place, creating it when missing.
    /// Use for capture/drop.md; inbox and attic keep atomic writes.
    public func writeStringInPlace(_ string: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(string.utf8)
        #if canImport(Darwin)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { actualURL in
            do {
                if fm.fileExists(atPath: actualURL.path) {
                    let handle = try FileHandle(forWritingTo: actualURL)
                    defer { try? handle.close() }
                    try handle.truncate(atOffset: 0)
                    try handle.write(contentsOf: data)
                    try handle.synchronize()
                } else {
                    try data.write(to: actualURL, options: [])
                }
            } catch {
                writeError = error
            }
        }
        if let error = writeError { throw error }
        if let error = coordinationError { throw error }
        #else
        if fm.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: [])
        }
        #endif
    }

    /// Prevent-loss safety net: keep a local NSFileVersion snapshot before risky rewrites.
    /// Versions are per-device; iCloud does not sync them. No-op except macOS; adding versions is a macOS-only API.
    public func snapshot(_ url: URL) {
        #if os(macOS)
        guard fm.fileExists(atPath: url.path) else { return }
        _ = try? NSFileVersion.addOfItem(at: url, withContentsOf: url, options: [])
        #endif
    }

    public func modificationDate(of url: URL) -> Date? {
        (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
}

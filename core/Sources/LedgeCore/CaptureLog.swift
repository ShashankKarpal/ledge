// The capture log: a device-local, append-only, NEVER-PRUNED record of every
// thought this device has captured, written BEFORE the capture is stored
// anywhere else and never deleted afterwards.
//
// This is a write-ahead log, and it is the last line of defence. Everything
// else in Ledge can fail: the iCloud folder can be unreachable, the security
// grant can die on reinstall, a merge can go wrong, the sync daemon can wedge,
// and an AI maintaining this code can introduce a regression (three were
// introduced during two days of fixing bugs in September 2026). None of that
// can reach this file, because it lives outside the synced folder, is only
// ever appended to, and is written before the risky part begins.
//
// Its purpose is to change the worst outcome from "a thought is gone" to "a
// thought needs restoring". Both independent reviews of this app ranked it as
// the largest reduction in the chance of losing a capture per unit of new
// code, ahead of both a storage rewrite and a second sync transport.
//
// It is also migration insurance: a complete per-device record to verify any
// future import against.
//
// Privacy: this file DOES contain your capture text, because a log that does
// not could not restore anything. It never leaves the device, and it is not in
// the synced folder. That is the opposite trade from incidents.log, which
// leaves the device and therefore holds no text at all.
//
// Built by Claude (Anthropic).

import Foundation

/// One capture, as recorded at the moment it was made.
public struct LoggedCapture: Codable, Equatable {
    /// Stable identity, also used as the spool delivery id where one applies,
    /// so a log entry can be matched to what reached the folder.
    public var id: String
    public var at: Date
    public var device: String
    public var text: String
    /// Where the capture was headed. Recorded before the attempt, so a crash
    /// mid-write leaves an entry that says what was being tried.
    public var intent: String
    /// Set once the capture is known to have reached a durable shared store.
    /// An entry that never gets confirmed is exactly what recovery looks for.
    public var confirmedAt: Date?

    public init(
        id: String = UUID().uuidString,
        at: Date = Date(),
        device: String,
        text: String,
        intent: String,
        confirmedAt: Date? = nil
    ) {
        self.id = id
        self.at = at
        self.device = device
        self.text = text
        self.intent = intent
        self.confirmedAt = confirmedAt
    }
}

public final class CaptureLog {
    public let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    /// The default per-device location. Application Support on macOS, the
    /// app's own Documents on iOS. Outside the iCloud folder on purpose: the
    /// whole point is to survive the folder being unreachable, wedged, or
    /// re-granted.
    public static func defaultURL() -> URL {
        let fm = FileManager.default
        #if os(macOS)
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ledge", isDirectory: true)
        #else
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("capture-log.jsonl")
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Record a capture before attempting to store it. Returns the entry so
    /// the caller can confirm it later. Throws only when the log itself cannot
    /// be written, which the caller must treat as serious: it means the last
    /// line of defence is gone and the capture should not be acknowledged.
    @discardableResult
    public func record(
        text: String,
        device: String,
        intent: String,
        id: String = UUID().uuidString,
        at: Date = Date()
    ) throws -> LoggedCapture {
        let entry = LoggedCapture(id: id, at: at, device: device, text: text, intent: intent)
        let data = try Self.encoder.encode(entry)
        lock.lock()
        defer { lock.unlock() }
        try LedgeStore.appendLine(String(decoding: data, as: UTF8.self), to: url)
        return entry
    }

    /// Note that a capture reached a durable shared store. Appends a
    /// confirmation line rather than rewriting the entry, because this file is
    /// append-only: rewriting is the exact operation that has caused every
    /// data-loss bug in this project.
    public func confirm(_ id: String, at date: Date = Date()) {
        let confirmation = LoggedCapture(
            id: id, at: date, device: "", text: "", intent: "confirm", confirmedAt: date
        )
        guard let data = try? Self.encoder.encode(confirmation) else { return }
        lock.lock()
        defer { lock.unlock() }
        try? LedgeStore.appendLine(String(decoding: data, as: UTF8.self), to: url)
    }

    /// Every line, in order. A corrupt line is skipped, never fatal.
    public func entries() -> [LoggedCapture] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return raw.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
            return try? Self.decoder.decode(LoggedCapture.self, from: data)
        }
    }

    /// Captures this device recorded that were never confirmed AND cannot be
    /// found in the inbox now. These are the ones a human should look at.
    ///
    /// Matching is by text plus minute, not by id, because a capture can reach
    /// the inbox through the spool, a drain on another device, or a merge, and
    /// only the text survives all of those paths intact.
    public func unrecovered(comparedTo inbox: Inbox, now: Date = Date(), ignoringNewerThan grace: TimeInterval = 300) -> [LoggedCapture] {
        let all = entries()
        let confirmed = Set(all.filter { $0.intent == "confirm" }.map(\.id))
        let present = Set(inbox.allEntries().map { pair in
            LedgeFormat.timeFormatter.string(from: pair.entry.timestamp) + "|" + LedgeFormat.trimEdges(pair.entry.text)
        })
        return all.filter { entry in
            guard entry.intent != "confirm" else { return false }
            guard !confirmed.contains(entry.id) else { return false }
            // A capture made seconds ago has not had time to land.
            guard now.timeIntervalSince(entry.at) > grace else { return false }
            let key = LedgeFormat.timeFormatter.string(from: entry.at) + "|" + LedgeFormat.trimEdges(entry.text)
            return !present.contains(key)
        }
    }

    /// Everything captured on this device, oldest first, as Markdown. The
    /// manual escape hatch: if all else fails, this file plus this function
    /// reconstruct the thoughts, with no app and no AI involved.
    public func exportMarkdown() -> String {
        let real = entries().filter { $0.intent != "confirm" }
        guard !real.isEmpty else { return "" }
        var out: [String] = ["# Ledge capture log export", ""]
        for entry in real.sorted(by: { $0.at < $1.at }) {
            out.append("### " + LedgeFormat.spoolFormatter.string(from: entry.at) + " · " + entry.device)
            out.append(entry.text)
            out.append("")
        }
        return out.joined(separator: "\n")
    }
}

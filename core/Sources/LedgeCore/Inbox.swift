// The inbox model: parse, serialize, prepend, fold. Days newest-first, entries newest-first.
// Built by Claude (Anthropic).

import Foundation

public struct Entry: Identifiable {
    /// Derived, not random: the inbox is re-parsed every two seconds on iOS and
    /// a fresh UUID per parse made SwiftUI rebuild the whole list each tick
    /// (lost scroll position, animation churn). Minute stamp, device and text
    /// identify an entry as well as the file format itself can.
    public var id: String {
        LedgeFormat.spoolFormatter.string(from: timestamp) + "|" + (device ?? "") + "|" + String(text.hashValue)
    }
    public var timestamp: Date
    public var text: String
    /// Which device captured this entry (iPhone, iPad, Apple Watch, a Mac name). Optional.
    public var device: String?

    public init(timestamp: Date, text: String, device: String? = nil) {
        self.timestamp = timestamp
        self.text = text
        self.device = device
    }
}

extension Entry: Equatable {
    public static func == (lhs: Entry, rhs: Entry) -> Bool {
        lhs.timestamp == rhs.timestamp && lhs.text == rhs.text
    }
}

public struct DaySection: Equatable {
    /// Canonical key, `yyyy-MM-dd`.
    public var day: String
    /// Rare content between the day header and the first entry; preserved verbatim.
    public var freeText: String
    public var entries: [Entry]

    public var date: Date? { LedgeFormat.dayFormatter.date(from: day) }

    public init(day: String, freeText: String = "", entries: [Entry] = []) {
        self.day = day
        self.freeText = freeText
        self.entries = entries
    }
}

public struct Inbox: Equatable {
    /// Text before the first day header; preserved verbatim.
    public var preamble: String
    public var days: [DaySection]

    public init(preamble: String = "", days: [DaySection] = []) {
        self.preamble = preamble
        self.days = days
    }

    // MARK: Parse

    public static func parse(_ text: String) -> Inbox {
        parseReporting(text).inbox
    }

    /// One human-readable line per structural repair the parser had to make.
    /// Empty for a well-formed file. Callers that persist the result should
    /// save when this is non-empty, so the serializer writes the healed form.
    public struct ParseReport: Equatable {
        public var inbox: Inbox
        public var repairs: [String]
    }

    /// Parse leniently and say what was repaired. The strict grammar is what
    /// the serializer writes; the reader accepts the damage a raw text editor
    /// can do to machine-written lines and reports it instead of hiding it
    /// (incident 2026-09-03: a backtick on a day header made a morning's
    /// entries invisible on the phone while the Mac showed them as normal).
    public static func parseReporting(_ text: String) -> ParseReport {
        var preambleLines: [String] = []
        var days: [DaySection] = []
        var repairs: [String] = []

        var dayKey: String?
        var freeLines: [String] = []
        var entries: [Entry] = []
        var entryTime: String?
        var entryLines: [String] = []

        func flushEntry() {
            guard let time = entryTime, let dk = dayKey else {
                entryTime = nil
                entryLines = []
                return
            }
            var timePart = time
            var device: String?
            if let sep = time.range(of: " · ") {
                timePart = String(time[..<sep.lowerBound])
                let tag = String(time[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
                device = tag.isEmpty ? nil : tag
            }
            let stamp = LedgeFormat.spoolFormatter.date(from: dk + " " + timePart) ?? Date.distantPast
            let body = LedgeFormat.trimEdges(entryLines.joined(separator: "\n"))
            entries.append(Entry(timestamp: stamp, text: body, device: device))
            entryTime = nil
            entryLines = []
        }

        func flushDay() {
            flushEntry()
            if let dk = dayKey {
                let section = DaySection(
                    day: dk,
                    freeText: LedgeFormat.trimEdges(freeLines.joined(separator: "\n")),
                    entries: entries
                )
                if let existing = days.firstIndex(where: { $0.day == dk }) {
                    // Two sections for one day happen when a damaged header
                    // hid the first one from a writer that then created a
                    // second. Merge, newest first, dropping exact twins.
                    var merged = Inbox(days: [days[existing]])
                    for entry in section.entries.reversed() {
                        _ = merged.fold([(date: entry.timestamp, text: entry.text, device: entry.device)])
                    }
                    if !section.freeText.isEmpty {
                        let free = merged.days[0].freeText
                        merged.days[0].freeText = free.isEmpty ? section.freeText : free + "\n" + section.freeText
                    }
                    days[existing] = merged.days[0]
                    repairs.append("merged a second section for " + dk)
                } else {
                    days.append(section)
                }
            }
            dayKey = nil
            freeLines = []
            entries = []
        }

        for line in text.components(separatedBy: "\n") {
            if let header = LedgeFormat.dayHeaderKey(line) {
                flushDay()
                dayKey = header.day
                if !header.junk.isEmpty {
                    repairs.append("repaired the day header for " + header.day)
                    // Junk that carries words is kept as the day's free text
                    // so nothing typed is lost; punctuation-only junk (a
                    // stray backtick) is dropped.
                    if header.junk.rangeOfCharacter(from: .alphanumerics) != nil {
                        freeLines.append(header.junk)
                    }
                }
            } else if dayKey != nil, LedgeFormat.isEntryHeader(line) {
                flushEntry()
                entryTime = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if entryTime != nil {
                entryLines.append(line)
            } else if dayKey != nil {
                freeLines.append(line)
            } else {
                preambleLines.append(line)
            }
        }
        flushDay()

        // Days are written newest first. A merge above can leave them out of
        // order; keys are yyyy-MM-dd so a string sort is chronological.
        let sorted = days.sorted { $0.day > $1.day }
        if sorted.map(\.day) != days.map(\.day) {
            repairs.append("reordered days newest first")
        }

        return ParseReport(
            inbox: Inbox(
                preamble: LedgeFormat.trimEdges(preambleLines.joined(separator: "\n")),
                days: sorted
            ),
            repairs: repairs
        )
    }

    // MARK: Serialize

    public func serialized() -> String {
        var out: [String] = []
        if !preamble.isEmpty {
            out.append(preamble)
            out.append("")
        }
        for day in days {
            out.append(LedgeFormat.dayHeaderPrefix + day.day)
            if !day.freeText.isEmpty {
                out.append(day.freeText)
                out.append("")
            }
            for entry in day.entries {
                var header = LedgeFormat.entryHeaderPrefix + LedgeFormat.timeFormatter.string(from: entry.timestamp)
                if let device = entry.device, !device.isEmpty {
                    header += " · " + device
                }
                out.append(header)
                if !entry.text.isEmpty {
                    out.append(entry.text)
                }
                out.append("")
            }
        }
        var result = out.joined(separator: "\n")
        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }

    // MARK: Mutation

    /// Insert a new entry at the correct position (newest first). Creates the day if needed.
    public mutating func prepend(text: String, at date: Date, device: String? = nil) {
        let stamp = LedgeFormat.minutePrecision(date)
        let dayKey = LedgeFormat.dayFormatter.string(from: stamp)
        let entry = Entry(timestamp: stamp, text: LedgeFormat.escapingStructure(LedgeFormat.trimEdges(text)), device: device)

        if let dayIndex = days.firstIndex(where: { $0.day == dayKey }) {
            let insertAt = days[dayIndex].entries.firstIndex(where: { $0.timestamp <= entry.timestamp })
                ?? days[dayIndex].entries.count
            days[dayIndex].entries.insert(entry, at: insertAt)
        } else {
            // Day keys are yyyy-MM-dd, so plain string comparison sorts chronologically.
            let insertAt = days.firstIndex(where: { $0.day < dayKey }) ?? days.count
            days.insert(DaySection(day: dayKey, entries: [entry]), at: insertAt)
        }
    }

    /// Fold external captures (spool drain, conflict merge) into the inbox.
    /// Duplicates (same day, same minute, same text) are skipped. Returns entries added.
    @discardableResult
    public mutating func fold(_ captures: [(date: Date, text: String)]) -> Int {
        fold(captures.map { (date: $0.date, text: $0.text, device: nil) })
    }

    @discardableResult
    public mutating func fold(_ captures: [(date: Date, text: String, device: String?)]) -> Int {
        var added = 0
        for capture in captures {
            let text = LedgeFormat.trimEdges(capture.text)
            if text.isEmpty { continue }
            let dayKey = LedgeFormat.dayFormatter.string(from: capture.date)
            let minute = LedgeFormat.timeFormatter.string(from: capture.date)
            if let dayIndex = days.firstIndex(where: { $0.day == dayKey }),
               days[dayIndex].entries.contains(where: {
                   $0.text == text && LedgeFormat.timeFormatter.string(from: $0.timestamp) == minute
               }) {
                continue
            }
            prepend(text: text, at: capture.date, device: capture.device)
            added += 1
        }
        return added
    }

    /// Collapse entries that are byte-identical twins (same minute, same text,
    /// same device) down to one. Run only as part of corruption repair: the
    /// null-byte incident of 2026-08-17 showed that corruption inside an entry
    /// body defeats fold's text dedupe, so the duplicate and the corruption
    /// arrive together and should be cleaned together. Returns entries removed.
    @discardableResult
    public mutating func collapseExactDuplicates() -> Int {
        var removed = 0
        for index in days.indices {
            var seen = Set<String>()
            var kept: [Entry] = []
            for entry in days[index].entries {
                let key = LedgeFormat.spoolFormatter.string(from: entry.timestamp)
                    + "|" + (entry.device ?? "") + "|" + entry.text
                if seen.insert(key).inserted {
                    kept.append(entry)
                } else {
                    removed += 1
                }
            }
            days[index].entries = kept
        }
        return removed
    }

    /// Drop entries whose text is empty (e.g. a summon that captured nothing), then empty days.
    public mutating func removeEmptyEntries() {
        for index in days.indices {
            days[index].entries.removeAll { $0.text.isEmpty }
        }
        days.removeAll { $0.entries.isEmpty && $0.freeText.isEmpty }
    }

    /// All entries, newest first, with their day key.
    public func allEntries() -> [(day: String, entry: Entry)] {
        days.flatMap { day in day.entries.map { (day.day, $0) } }
    }
}

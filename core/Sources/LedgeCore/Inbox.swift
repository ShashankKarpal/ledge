// The inbox model: parse, serialize, prepend, fold. Days newest-first, entries newest-first.
// Built by Claude (Anthropic).

import Foundation

public struct Entry: Identifiable {
    public let id = UUID()
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
        var preambleLines: [String] = []
        var days: [DaySection] = []

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
                days.append(DaySection(
                    day: dk,
                    freeText: LedgeFormat.trimEdges(freeLines.joined(separator: "\n")),
                    entries: entries
                ))
            }
            dayKey = nil
            freeLines = []
            entries = []
        }

        for line in text.components(separatedBy: "\n") {
            if LedgeFormat.isDayHeader(line) {
                flushDay()
                dayKey = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
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

        return Inbox(
            preamble: LedgeFormat.trimEdges(preambleLines.joined(separator: "\n")),
            days: days
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
        let entry = Entry(timestamp: stamp, text: LedgeFormat.trimEdges(text), device: device)

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

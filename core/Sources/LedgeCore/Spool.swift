// The capture spool: capture/drop.md, written by Shortcuts and the watch relay,
// drained by the apps. Format: `[[yyyy-MM-dd HH:mm]] text`, one capture per marker.
// Built by Claude (Anthropic).

import Foundation

public enum Spool {
    /// Parse spool content into captures. Unmarked leading text becomes one capture
    /// stamped with `fallbackDate` (callers pass the file's modification time).
    /// Null bytes are corruption, never content, and are scrubbed before parsing.
    public static func parse(_ text: String, fallbackDate: Date) -> [(date: Date, text: String, device: String?, id: String?)] {
        var captures: [(date: Date, text: String, device: String?, id: String?)] = []
        var leadingLines: [String] = []
        var currentDate: Date?
        var currentDevice: String?
        var currentID: String?
        var currentLines: [String] = []

        func flush() {
            if let date = currentDate {
                let body = LedgeFormat.trimEdges(currentLines.joined(separator: "\n"))
                if !body.isEmpty {
                    captures.append((date, body, currentDevice, currentID))
                }
            }
            currentLines = []
        }

        for line in LedgeFormat.strippingNulls(text).components(separatedBy: "\n") {
            if let (date, device, id, rest) = markerMatch(line) {
                flush()
                currentDate = date
                currentDevice = device
                currentID = id
                currentLines = [rest]
            } else if currentDate != nil {
                currentLines.append(line)
            } else {
                leadingLines.append(line)
            }
        }
        flush()

        let leading = LedgeFormat.trimEdges(leadingLines.joined(separator: "\n"))
        if !leading.isEmpty {
            captures.insert((fallbackDate, leading, nil, nil), at: 0)
        }
        return captures
    }

    /// Matches `[[yyyy-MM-dd HH:mm]]` at the start of a line, with optional
    /// ` · device` and ` · #id` fields in the stamp; returns the date, optional
    /// device, optional capture id, and the rest of the line.
    static func markerMatch(_ line: String) -> (Date, String?, String?, String)? {
        guard line.hasPrefix("[[") else { return nil }
        guard let close = line.range(of: "]]") else { return nil }
        let stampStart = line.index(line.startIndex, offsetBy: 2)
        guard stampStart <= close.lowerBound else { return nil }
        let stamp = String(line[stampStart..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
        let fields = stamp.components(separatedBy: " · ")
        guard let date = LedgeFormat.spoolFormatter.date(from: fields[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        var device: String?
        var id: String?
        for field in fields.dropFirst() {
            let tag = field.trimmingCharacters(in: .whitespaces)
            if tag.hasPrefix("#") {
                let value = String(tag.dropFirst())
                if !value.isEmpty { id = value }
            } else if !tag.isEmpty {
                device = tag
            }
        }
        var rest = String(line[close.upperBound...])
        if rest.hasPrefix(" ") { rest.removeFirst() }
        return (date, device, id, rest)
    }

    /// Render a capture as a spool line (used by the watch relay and tests).
    /// The optional id is the capture's delivery UUID: the watch relay can hand
    /// the same capture over twice (a live message whose reply timed out, then
    /// the queued fallback), and the id is what lets the drain drop the copy.
    public static func line(for text: String, at date: Date, device: String? = nil, id: String? = nil) -> String {
        var stamp = LedgeFormat.spoolFormatter.string(from: date)
        if let device, !device.isEmpty {
            stamp += " · " + device
        }
        if let id, !id.isEmpty {
            stamp += " · #" + id
        }
        return "[[" + stamp + "]] " + text
    }

    /// Count what is waiting in spool-format text (drop.md or a pending queue)
    /// without folding anything. The capture-trust check: surfaces call this
    /// after a drain attempt, so anything counted here is stuck, not in flight.
    public static func status(_ text: String, fallbackDate: Date) -> SpoolStatus {
        let captures = parse(text, fallbackDate: fallbackDate)
        return SpoolStatus(count: captures.count, oldest: captures.map(\.date).min())
    }
}

/// The waiting-capture summary behind the muted capture-trust line. A capture
/// once sat in the spool for eleven days with zero indication on any surface;
/// this type exists so that can never be invisible again.
public struct SpoolStatus: Equatable {
    public let count: Int
    public let oldest: Date?

    public static let empty = SpoolStatus(count: 0, oldest: nil)

    public init(count: Int, oldest: Date?) {
        self.count = count
        self.oldest = oldest
    }

    /// Combine the spool and the local pending queue into one summary.
    public func merged(with other: SpoolStatus) -> SpoolStatus {
        SpoolStatus(
            count: count + other.count,
            oldest: [oldest, other.oldest].compactMap { $0 }.min()
        )
    }

    /// A capture still waiting after this long is stuck, not in flight.
    public func isStale(now: Date = Date(), threshold: TimeInterval = 3600) -> Bool {
        guard let oldest else { return false }
        return now.timeIntervalSince(oldest) > threshold
    }

    /// The muted in-surface line, shared by every platform so the copy never
    /// drifts. Nil when nothing is waiting: the healthy case shows nothing,
    /// per the no-badges rule. Stale captures name their date so an old
    /// stranding reads as old.
    public func waitingLine(now: Date = Date()) -> String? {
        guard count > 0 else { return nil }
        let noun = count == 1 ? "1 capture waiting" : "\(count) captures waiting"
        if let oldest, isStale(now: now) {
            return noun + " since " + LedgeFormat.spoolFormatter.string(from: oldest)
        }
        return noun
    }
}

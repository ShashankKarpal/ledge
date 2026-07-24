// The capture spool: capture/drop.md, written by Shortcuts and the watch relay,
// drained by the apps. Format: `[[yyyy-MM-dd HH:mm]] text`, one capture per marker.
// Built by Claude (Anthropic).

import Foundation

public enum Spool {
    /// Parse spool content into captures. Unmarked leading text becomes one capture
    /// stamped with `fallbackDate` (callers pass the file's modification time).
    public static func parse(_ text: String, fallbackDate: Date) -> [(date: Date, text: String, device: String?)] {
        var captures: [(date: Date, text: String, device: String?)] = []
        var leadingLines: [String] = []
        var currentDate: Date?
        var currentDevice: String?
        var currentLines: [String] = []

        func flush() {
            if let date = currentDate {
                let body = LedgeFormat.trimEdges(currentLines.joined(separator: "\n"))
                if !body.isEmpty {
                    captures.append((date, body, currentDevice))
                }
            }
            currentLines = []
        }

        for line in text.components(separatedBy: "\n") {
            if let (date, device, rest) = markerMatch(line) {
                flush()
                currentDate = date
                currentDevice = device
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
            captures.insert((fallbackDate, leading, nil), at: 0)
        }
        return captures
    }

    /// Matches `[[yyyy-MM-dd HH:mm]]` or `[[yyyy-MM-dd HH:mm · device]]` at the
    /// start of a line; returns the date, optional device, and the rest.
    static func markerMatch(_ line: String) -> (Date, String?, String)? {
        guard line.hasPrefix("[[") else { return nil }
        guard let close = line.range(of: "]]") else { return nil }
        let stampStart = line.index(line.startIndex, offsetBy: 2)
        guard stampStart <= close.lowerBound else { return nil }
        var stamp = String(line[stampStart..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
        var device: String?
        if let sep = stamp.range(of: " · ") {
            let tag = String(stamp[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
            device = tag.isEmpty ? nil : tag
            stamp = String(stamp[..<sep.lowerBound])
        }
        guard let date = LedgeFormat.spoolFormatter.date(from: stamp) else { return nil }
        var rest = String(line[close.upperBound...])
        if rest.hasPrefix(" ") { rest.removeFirst() }
        return (date, device, rest)
    }

    /// Render a capture as a spool line (used by the watch relay and tests).
    public static func line(for text: String, at date: Date, device: String? = nil) -> String {
        var stamp = LedgeFormat.spoolFormatter.string(from: date)
        if let device, !device.isEmpty {
            stamp += " · " + device
        }
        return "[[" + stamp + "]] " + text
    }
}

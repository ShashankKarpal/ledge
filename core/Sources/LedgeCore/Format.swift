// Ledge file-format primitives. The normative contract is docs/file-format.md.
// Built by Claude (Anthropic).

import Foundation

public enum LedgeFormat {
    public static let dayHeaderPrefix = "## "
    public static let entryHeaderPrefix = "### "

    // en_US_POSIX keeps the on-disk format stable regardless of device locale.
    public static let dayFormatter: DateFormatter = makeFormatter("yyyy-MM-dd")
    public static let timeFormatter: DateFormatter = makeFormatter("HH:mm")
    public static let spoolFormatter: DateFormatter = makeFormatter("yyyy-MM-dd HH:mm")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = format
        return f
    }

    /// Exactly `## yyyy-MM-dd`, nothing else. `## Ideas` is ordinary content.
    /// This is the canonical form the serializer writes. Readers use the
    /// lenient `dayHeaderKey` so a damaged header is still recognised.
    public static func isDayHeader(_ line: String) -> Bool {
        line.range(of: "^## \\d{4}-\\d{2}-\\d{2}\\s*$", options: .regularExpression) != nil
    }

    /// Lenient day-header recognition for readers. A line that starts with
    /// `## ` and a real yyyy-MM-dd date is that day, whatever follows the date.
    /// Returns the day key plus any trailing junk (trimmed, possibly empty).
    ///
    /// Why (incident 2026-09-03): the Mac editor is a raw text view over the
    /// whole file, and one stray keystroke on the machine-written header line
    /// (`## 2026-09-03` with a backtick glued on) made the strict regex fail.
    /// The parser then demoted every entry under it to preamble, which the Mac
    /// renders as normal text and the phone does not render at all. Sync looked
    /// dead for a morning while the bytes were identical on both devices.
    public static func dayHeaderKey(_ line: String) -> (day: String, junk: String)? {
        guard line.hasPrefix(dayHeaderPrefix) else { return nil }
        let rest = String(line.dropFirst(dayHeaderPrefix.count)).trimmingCharacters(in: .whitespaces)
        guard rest.count >= 10 else { return nil }
        let candidate = String(rest.prefix(10))
        guard candidate.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil,
              dayFormatter.date(from: candidate) != nil else { return nil }
        let junk = String(rest.dropFirst(10)).trimmingCharacters(in: .whitespaces)
        return (candidate, junk)
    }

    /// `### HH:mm` with an optional ` · <device>` suffix. `### Plan` is ordinary content.
    public static func isEntryHeader(_ line: String) -> Bool {
        line.range(of: "^### \\d{2}:\\d{2}( · .+)?\\s*$", options: .regularExpression) != nil
    }

    /// Defuse lines inside captured text that the parsers would otherwise read
    /// as structure: a day header, an entry header, or a spool capture marker.
    /// Shared web pages, Shortcut input and Watch relay text are untrusted;
    /// without this a pasted `### 09:00 · iPhone` split an entry and forged its
    /// attribution, and a `[[2020-01-01 00:00 ...]]` line forged a past capture
    /// that the Attic then buried (audit 2026-09-02). A zero-width space in
    /// front keeps the text visually identical and the regexes cold.
    public static func escapingStructure(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            // Lenient day check on purpose: whatever the reader would take as
            // structure, the writer must defuse, or the two drift apart.
            (dayHeaderKey(line) != nil || isEntryHeader(line) || line.hasPrefix("[[")) ? "\u{200B}" + line : line
        }.joined(separator: "\n")
    }

    /// Remove null bytes. Nulls are never legitimate Ledge content; they appear
    /// only as corruption from interrupted or racing file writes (a 588-byte
    /// null run landed in the live inbox on 2026-08-17). Every real character
    /// is preserved.
    public static func strippingNulls(_ text: String) -> String {
        guard text.contains("\u{0000}") else { return text }
        return text.replacingOccurrences(of: "\u{0000}", with: "")
    }

    /// Trim leading and trailing whitespace-only lines, preserve interior blanks.
    public static func trimEdges(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// Filename slug: lowercase, alphanumerics kept, everything else collapses to single hyphens.
    public static func slug(_ title: String, maxLength: Int = 40) -> String {
        var out = ""
        var lastWasHyphen = true
        for scalar in title.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                out.append("-")
                lastWasHyphen = true
            }
            if out.count >= maxLength { break }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "note" : out
    }

    /// "4 hours ago", "2 days ago", "just now": the rough wording the sync
    /// health lines use. Shared so the copy never drifts between platforms.
    public static func roughAge(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60 { return "just now" }
        if s < 3600 {
            let m = Int(s / 60)
            return m == 1 ? "1 minute ago" : "\(m) minutes ago"
        }
        if s < 86400 {
            let h = Int(s / 3600)
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        }
        let d = Int(s / 86400)
        return d == 1 ? "1 day ago" : "\(d) days ago"
    }

    /// Truncate a Date to minute precision so timestamps round-trip exactly.
    public static func minutePrecision(_ date: Date) -> Date {
        let key = spoolFormatter.string(from: date)
        return spoolFormatter.date(from: key) ?? date
    }
}

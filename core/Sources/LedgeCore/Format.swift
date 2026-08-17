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
    public static func isDayHeader(_ line: String) -> Bool {
        line.range(of: "^## \\d{4}-\\d{2}-\\d{2}\\s*$", options: .regularExpression) != nil
    }

    /// `### HH:mm` with an optional ` · <device>` suffix. `### Plan` is ordinary content.
    public static func isEntryHeader(_ line: String) -> Bool {
        line.range(of: "^### \\d{2}:\\d{2}( · .+)?\\s*$", options: .regularExpression) != nil
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

    /// Truncate a Date to minute precision so timestamps round-trip exactly.
    public static func minutePrecision(_ date: Date) -> Date {
        let key = spoolFormatter.string(from: date)
        return spoolFormatter.date(from: key) ?? date
    }
}

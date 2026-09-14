// Merge as edit: when two copies of the same entry meet, decide whether they
// are one thought edited twice or two thoughts made in the same minute.
//
// The file format identifies an entry by day, minute and device. Until now
// every merge treated a same-minute, same-device entry with different text
// as a second entry, so ticking a checkbox on the phone while the Mac held a
// stale copy resurrected the unticked twin on the next save, and a fixed
// typo became two entries (audit 2026-09-02, L-B3). The opposite mistake is
// worse: two genuine captures in one minute from one device (two Siri
// captures, two Watch relays) must never collapse into one. So the rule is
// narrow and testable:
//
// - RELATED means: equal after normalising checkbox marks (a toggle), or one
//   is a prefix of the other (typing continued), or the two share at least
//   half their lines, or share at least 60 percent of their characters as a
//   common prefix (a small fix inside a line). Anything else is two entries.
// - When related, the preferred side's text is kept and checkboxes are
//   UNIONED: a box ticked on either side stays ticked. A completion is never
//   undone by a merge, whichever side "wins".
// - Which side is preferred depends on the direction of the merge and is the
//   caller's decision: a save merging our newer state onto changed disk
//   bytes prefers the incoming text; folding an iCloud conflict version (the
//   loser of a race, older by construction) prefers the existing text; a
//   spool drain keeps both, always, because captures are not edits.
// Built by Claude (Anthropic).

import Foundation

public enum EditPolicy: Equatable {
    /// Never merge: two texts are two entries. Spool drains.
    case keepBoth
    /// Related texts collapse, the incoming text wins, checkboxes union.
    case incomingWins
    /// Related texts collapse, the existing text wins, checkboxes union.
    case existingWins
}

public enum EditMerge {
    static let checkedMarks = ["- [x]", "- [X]", "* [x]", "* [X]"]
    static let openMarks = ["- [ ]", "* [ ]"]

    /// A line with any checkbox mark reduced to its open form, so a toggle
    /// compares equal. Non-checkbox lines pass through trimmed.
    static func normalizedLine(_ line: String) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        for mark in checkedMarks where t.hasPrefix(mark) {
            return "- [ ]" + t.dropFirst(mark.count)
        }
        for mark in openMarks where t.hasPrefix(mark) {
            return "- [ ]" + t.dropFirst(mark.count)
        }
        return t
    }

    static func isChecked(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return checkedMarks.contains { t.hasPrefix($0) }
    }

    static func normalized(_ text: String) -> String {
        text.components(separatedBy: "\n").map(normalizedLine).joined(separator: "\n")
    }

    /// Are these two texts one thought, edited? See the file header for the rule.
    public static func areRelated(_ a: String, _ b: String) -> Bool {
        let na = LedgeFormat.trimEdges(normalized(a))
        let nb = LedgeFormat.trimEdges(normalized(b))
        if na == nb { return true }
        if na.isEmpty || nb.isEmpty { return false }
        if na.hasPrefix(nb) || nb.hasPrefix(na) { return true }

        let la = Set(na.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let lb = Set(nb.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let longer = max(la.count, lb.count)
        if longer > 1, Double(la.intersection(lb).count) / Double(longer) >= 0.5 { return true }

        let common = zip(na, nb).prefix { $0 == $1 }.count
        let maxLen = max(na.count, nb.count)
        return maxLen > 0 && Double(common) / Double(maxLen) >= 0.6
    }

    /// The merged text of two related copies: `preferred`'s text with every
    /// checkbox that is ticked in `other` ticked too. Boxes are matched by
    /// their normalised line; a line that exists only on one side keeps that
    /// side's state.
    public static func merged(preferred: String, other: String) -> String {
        let checkedElsewhere = Set(
            other.components(separatedBy: "\n").filter(isChecked).map(normalizedLine)
        )
        guard !checkedElsewhere.isEmpty else { return preferred }
        return preferred.components(separatedBy: "\n").map { line in
            let norm = normalizedLine(line)
            guard !isChecked(line), checkedElsewhere.contains(norm) else { return line }
            // Preserve the line's leading whitespace and its bullet character.
            let leading = line.prefix { $0 == " " || $0 == "\t" }
            let t = line.trimmingCharacters(in: .whitespaces)
            let bullet = t.first == "*" ? "*" : "-"
            return String(leading) + bullet + " [x]" + t.dropFirst(5)
        }.joined(separator: "\n")
    }
}

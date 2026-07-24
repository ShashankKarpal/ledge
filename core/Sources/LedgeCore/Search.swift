// Vague-memory search (fuzzy, typo-tolerant-ish, recency-weighted) and the Open Loops scanner.
// Built by Claude (Anthropic).

import Foundation

public struct SearchHit: Identifiable {
    public let id = UUID()
    public let fileURL: URL
    public let title: String
    public let snippet: String
    public let when: Date?
    public let score: Double
}

public struct OpenLoop: Identifiable {
    public let id = UUID()
    public let fileURL: URL
    public let text: String
    public let when: Date?
    public let sourceLabel: String
}

public extension LedgeStore {

    // MARK: Search

    func search(_ query: String, inbox: Inbox, limit: Int = 40, now: Date = Date()) -> [SearchHit] {
        let tokens = query.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        var hits: [SearchHit] = []

        // Inbox entries
        for (day, entry) in inbox.allEntries() {
            appendHit(&hits, text: entry.text, tokens: tokens, now: now,
                      fileURL: inboxURL,
                      title: "Inbox · " + day + " " + LedgeFormat.timeFormatter.string(from: entry.timestamp),
                      when: entry.timestamp)
        }

        // Notes (whole file, weighted by modification date)
        for url in (try? noteURLs()) ?? [] {
            guard let content2 = try? readString(url) else { continue }
            let modified = modificationDate(of: url)
            appendHit(&hits, text: content2, tokens: tokens, now: now,
                      fileURL: url,
                      title: LedgeStore.title(of: content2, fallback: url.lastPathComponent),
                      when: modified)
        }

        // Attic months (parsed as inbox files, real timestamps preserved)
        for url in (try? atticMonthURLs()) ?? [] {
            guard let content2 = try? readString(url) else { continue }
            let atticInbox = Inbox.parse(content2)
            for (day, entry) in atticInbox.allEntries() {
                appendHit(&hits, text: entry.text, tokens: tokens, now: now,
                          fileURL: url,
                          title: "Attic · " + day + " " + LedgeFormat.timeFormatter.string(from: entry.timestamp),
                          when: entry.timestamp)
            }
        }

        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    private func appendHit(_ hits: inout [SearchHit], text: String, tokens: [String], now: Date,
                           fileURL: URL, title: String, when: Date?) {
        let match = Self.matchScore(text, tokens: tokens)
        guard match > 0 else { return }
        let score = match * Self.recencyBoost(when, now: now)
        hits.append(SearchHit(
            fileURL: fileURL,
            title: title,
            snippet: Self.snippet(of: text, firstToken: tokens[0]),
            when: when,
            score: score
        ))
    }

    /// Every token must land: exact substring scores 2, in-order subsequence scores 0.6.
    static func matchScore(_ text: String, tokens: [String]) -> Double {
        let haystack = text.lowercased()
        var total = 0.0
        for token in tokens {
            if haystack.contains(token) {
                total += 2.0
            } else if isSubsequence(token, of: haystack) {
                total += 0.6
            } else {
                return 0
            }
        }
        return total
    }

    /// Fresh things surface first; a hit ages to half weight in about two weeks.
    static func recencyBoost(_ when: Date?, now: Date) -> Double {
        guard let when else { return 0.4 }
        let days = max(0, now.timeIntervalSince(when) / 86_400)
        return 1.0 / (1.0 + days / 14.0)
    }

    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var needleIndex = needle.startIndex
        for character in haystack {
            if character == needle[needleIndex] {
                needleIndex = needle.index(after: needleIndex)
                if needleIndex == needle.endIndex { return true }
            }
        }
        return false
    }

    static func snippet(of text: String, firstToken: String, maxLength: Int = 140) -> String {
        let lines = text.components(separatedBy: "\n")
        let line = lines.first { $0.lowercased().contains(firstToken) } ?? lines.first ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= maxLength ? trimmed : String(trimmed.prefix(maxLength)) + "…"
    }

    // MARK: Open Loops

    /// Every unchecked checkbox in the inbox and notes (the Attic rests), newest first.
    /// Pull, not push: no badges, no counts on icons, no red anywhere.
    func openLoops(inbox: Inbox) -> [OpenLoop] {
        var loops: [OpenLoop] = []

        for (day, entry) in inbox.allEntries() {
            for line in entry.text.components(separatedBy: "\n") where Self.isOpenCheckbox(line) {
                loops.append(OpenLoop(
                    fileURL: inboxURL,
                    text: Self.taskText(line),
                    when: entry.timestamp,
                    sourceLabel: "Inbox · " + day
                ))
            }
        }

        for url in (try? noteURLs()) ?? [] {
            guard let content2 = try? readString(url) else { continue }
            let modified = modificationDate(of: url)
            let title = LedgeStore.title(of: content2, fallback: url.lastPathComponent)
            for line in content2.components(separatedBy: "\n") where Self.isOpenCheckbox(line) {
                loops.append(OpenLoop(
                    fileURL: url,
                    text: Self.taskText(line),
                    when: modified,
                    sourceLabel: title
                ))
            }
        }

        return loops.sorted { ($0.when ?? .distantPast) > ($1.when ?? .distantPast) }
    }

    static func isOpenCheckbox(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("* [ ]")
    }

    static func taskText(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }
}

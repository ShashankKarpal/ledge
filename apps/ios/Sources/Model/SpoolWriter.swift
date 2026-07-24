// Shared capture helper for out-of-app writers (App Intents, watch relay).
// Writes Spool lines into capture/drop.md, never edits inbox.md directly.
// When the folder is unreachable the capture lands in a local pending queue
// that the app flushes on its next launch. Capture never fails.
// Built by Claude (Anthropic).

import Foundation
import LedgeCore

enum SpoolWriter {

    static let bookmarkKey = "ledge.folderBookmark"

    /// Local queue in the app's own Documents, used before a folder is
    /// connected or when the bookmark cannot be resolved right now.
    static var pendingURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("pending-captures.md")
    }

    /// Resolve the saved folder bookmark. When `started` is true the caller
    /// must balance with stopAccessingSecurityScopedResource().
    static func resolveRoot() -> (url: URL, started: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        let started = url.startAccessingSecurityScopedResource()
        return (url, started)
    }

    /// Append one capture to capture/drop.md, falling back to the pending queue.
    static func append(text: String, at date: Date, device: String? = nil) {
        let trimmed = LedgeFormat.trimEdges(text)
        guard !trimmed.isEmpty else { return }
        let line = Spool.line(for: trimmed, at: date, device: device)

        guard let resolved = resolveRoot() else {
            appendToPending(line)
            return
        }
        defer {
            if resolved.started { resolved.url.stopAccessingSecurityScopedResource() }
        }

        let store = LedgeStore(root: resolved.url)
        do {
            let existing = (try store.readString(store.spoolURL)) ?? ""
            var combined = existing
            if !combined.isEmpty && !combined.hasSuffix("\n") { combined += "\n" }
            combined += line + "\n"
            try store.writeString(combined, to: store.spoolURL)
        } catch {
            appendToPending(line)
        }
    }

    /// Append one already-formatted spool line to the local pending queue.
    static func appendToPending(_ line: String) {
        let url = pendingURL
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var combined = existing
        if !combined.isEmpty && !combined.hasSuffix("\n") { combined += "\n" }
        combined += line + "\n"
        try? combined.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Read the pending queue without touching it. Nil when nothing is waiting.
    static func pendingContents() -> String? {
        guard let raw = try? String(contentsOf: pendingURL, encoding: .utf8) else { return nil }
        return LedgeFormat.trimEdges(raw).isEmpty ? nil : raw
    }

    /// Clear the pending queue. Call only after its contents reached the spool.
    static func clearPending() {
        try? FileManager.default.removeItem(at: pendingURL)
    }
}

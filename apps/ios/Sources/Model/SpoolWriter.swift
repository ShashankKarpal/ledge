// Shared capture helper for out-of-app writers (App Intents, watch relay).
// Writes Spool lines into capture/drop.md, never edits inbox.md directly.
// When the folder is unreachable the capture lands in a local pending queue
// that the app flushes on its next launch. Capture never fails silently.
// Built by Claude (Anthropic).
//
// TRANSACTION RULE (review 2026-09-03). Every write here is ONE coordinated
// append. The previous shape read the file in one coordinated block and
// rewrote the whole file in another, which is not a lock: two App Intents, or
// an Intent and the watch relay, could both read the same bytes and the second
// rewrite would erase the first capture. Appending inside a single coordination
// block cannot lose a concurrent write, and it preserves the file's identity,
// which the Shortcuts "Append to Text File" bookmark depends on
// (incident 2026-07-27).

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

    /// Where a capture ended up. Callers that can tell the user the truth
    /// (App Intents, the watch relay) must branch on this instead of assuming.
    enum Landing: Equatable {
        /// Written into the shared folder's spool. Every device will see it.
        case spool
        /// Written to this device's local queue; it reaches the folder later.
        case pending
        /// Nothing was written anywhere. The capture is LOST unless the caller
        /// keeps it. Only returned when even the local queue write failed.
        case failed
    }

    /// Append one capture to capture/drop.md, falling back to the pending queue.
    /// `id` is the watch relay's delivery id; drain dedupes repeat deliveries by it.
    /// The device-local write-ahead log. Every capture is recorded here first,
    /// so nothing that happens afterwards can lose the thought entirely.
    static let log = CaptureLog(url: CaptureLog.defaultURL())

    @discardableResult
    static func append(text: String, at date: Date, device: String? = nil, id: String? = nil) -> Landing {
        let trimmed = LedgeFormat.trimEdges(text)
        guard !trimmed.isEmpty else { return .spool }

        // WRITE AHEAD, before anything that can fail. If the folder is gone,
        // the grant is dead, iCloud is wedged, or this process dies mid-write,
        // the thought is already on this device's disk in a file nothing else
        // touches.
        let deliveryID = id ?? UUID().uuidString
        let logged = try? log.record(
            text: trimmed,
            device: device ?? "iPhone",
            intent: "spool",
            id: deliveryID,
            at: date
        )

        let line = Spool.line(for: trimmed, at: date, device: device, id: deliveryID)

        guard let resolved = resolveRoot() else {
            return appendToPending(line)
        }
        defer {
            if resolved.started { resolved.url.stopAccessingSecurityScopedResource() }
        }

        let store = LedgeStore(root: resolved.url)
        do {
            try store.appendSpoolLine(line)
            if logged != nil { log.confirm(deliveryID) }
            return .spool
        } catch {
            return appendToPending(line)
        }
    }

    /// Append one already-formatted spool line to the local pending queue.
    /// Coordinated and append-only for the same reason as the spool: this is
    /// the last line of defence and it used to be an unchecked `try?` over a
    /// whole-file rewrite.
    @discardableResult
    static func appendToPending(_ line: String) -> Landing {
        do {
            try LedgeStore.appendLine(line, to: pendingURL)
            return .pending
        } catch {
            return .failed
        }
    }

    /// Read the pending queue without touching it. Nil when nothing is waiting.
    static func pendingContents() -> String? {
        guard let raw = try? String(contentsOf: pendingURL, encoding: .utf8) else { return nil }
        return LedgeFormat.trimEdges(raw).isEmpty ? nil : raw
    }

    /// Remove exactly the bytes that were successfully moved into the spool,
    /// leaving anything appended since. Clearing the whole file could discard a
    /// capture that arrived while the flush was in flight.
    static func consumePending(_ consumed: String) throws {
        try LedgeStore.consumePrefix(consumed, of: pendingURL)
    }
}

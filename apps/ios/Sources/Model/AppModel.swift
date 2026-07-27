// The app model: folder bookmark, LedgeStore, inbox state, calm notices.
// Built by Claude (Anthropic).

import Foundation
import SwiftUI
import UIKit
import EventKit
import LedgeCore

@MainActor
final class AppModel: ObservableObject {

    /// Parsed inbox, the single source of truth for the UI.
    @Published private(set) var inbox = Inbox()

    /// Calm amber banner text. Nil when everything is fine. Never alarmist.
    @Published var notice: String?

    /// True when a folder bookmark exists (drives setup vs inbox screen).
    @Published private(set) var hasFolder: Bool

    /// True when the bookmark resolved and the store is usable right now.
    @Published private(set) var isConnected = false

    private(set) var store: LedgeStore?
    private var rootURL: URL?
    private var settings = LedgeSettings.defaults

    init() {
        hasFolder = UserDefaults.standard.data(forKey: SpoolWriter.bookmarkKey) != nil
        restore()
    }

    // MARK: Folder connection

    /// Called from the folder picker. Bookmarks the folder and opens it.
    func connectFolder(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: SpoolWriter.bookmarkKey)
        } catch {
            notice = "Ledge could not remember that folder. Please pick it again."
            return
        }
        hasFolder = true
        openRoot(url)
    }

    /// Resolve the saved bookmark and open the store. Safe to call anytime.
    func restore() {
        guard let data = UserDefaults.standard.data(forKey: SpoolWriter.bookmarkKey) else {
            hasFolder = false
            return
        }
        hasFolder = true
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            isConnected = false
            notice = "Ledge lost access to your folder. Pick it again when you have a moment."
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(fresh, forKey: SpoolWriter.bookmarkKey)
        }
        openRoot(url)
    }

    private func openRoot(_ url: URL) {
        rootURL = url
        let store = LedgeStore(root: url)
        self.store = store
        do {
            try store.bootstrap()
            settings = LedgeSettings.load(from: store.settingsURL)
            isConnected = true
            flushPending()
            refresh()
        } catch {
            isConnected = false
            notice = "Ledge could not open your folder just now. Pull to refresh to try again."
        }
    }

    /// Called on scenePhase active. Reconnects if needed, then reloads and drains.
    func becameActive() {
        if store == nil || !isConnected {
            restore()
            return
        }
        flushPending()
        refresh()
    }

    /// Reload the inbox from disk, drain the spool, age old days, save if changed.
    func refresh() {
        guard let store else { return }
        do {
            var loaded = try store.loadInbox()
            let drained = try store.drainSpool(into: &loaded)
            let aged = try store.age(&loaded, olderThanDays: settings.agingDays)
            let journaled = reconcileJournal(into: &loaded)
            if drained + aged + journaled > 0 {
                try store.saveInbox(loaded)
            }
            inbox = loaded
            isConnected = true
            notice = nil
        } catch {
            notice = "Ledge could not read your folder just now. Pull to refresh to try again."
        }
    }

    // MARK: Capture

    /// Prepend a thought to the inbox. Never blocked: falls back to the
    /// pending queue when the folder is unreachable.
    func capture(text: String) {
        let trimmed = LedgeFormat.trimEdges(text)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        guard let store, isConnected else {
            queueWhenDisconnected(text: trimmed, at: now)
            return
        }
        var updated = inbox
        updated.prepend(text: trimmed, at: now, device: Self.deviceName)
        do {
            try store.saveInbox(updated)
            inbox = updated
            journalAdd(text: trimmed, at: now)
        } catch {
            SpoolWriter.appendToPending(Spool.line(for: trimmed, at: now, device: Self.deviceName))
            notice = "Captured to the local queue. Ledge will file it when the folder is reachable."
        }
    }

    /// Capture before any folder is connected: queue locally, flush later.
    func queueWhenDisconnected(text: String, at date: Date = Date()) {
        let trimmed = LedgeFormat.trimEdges(text)
        guard !trimmed.isEmpty else { return }
        SpoolWriter.appendToPending(Spool.line(for: trimmed, at: date, device: Self.deviceName))
        notice = "Captured. Ledge will file it once your folder is connected."
    }

    /// Move locally queued captures into the real spool, then clear the queue.
    func flushPending() {
        guard let store, isConnected else { return }
        guard let pending = SpoolWriter.pendingContents() else { return }
        do {
            let existing = (try store.readString(store.spoolURL)) ?? ""
            var combined = existing
            if !combined.isEmpty && !combined.hasSuffix("\n") { combined += "\n" }
            combined += pending
            if !combined.hasSuffix("\n") { combined += "\n" }
            try store.writeStringInPlace(combined, to: store.spoolURL)
            SpoolWriter.clearPending()
        } catch {
            notice = "Some captures are still in the local queue. They flush on the next refresh."
        }
    }

    // MARK: Foreground heartbeat

    /// While the app is on screen, re-check the inbox every couple of seconds:
    /// each pass nudges iCloud for newer bytes and reloads when the raw disk
    /// content actually changed. Stopped in the background; zero cost there.
    private var heartbeat: Timer?
    private var lastSeenDiskRaw = ""

    func startHeartbeat() {
        stopHeartbeat()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.heartbeatTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    func stopHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = nil
    }

    private func heartbeatTick() {
        guard let store, isConnected else { return }
        let raw = ((try? store.readString(store.inboxURL)) ?? nil) ?? ""
        if raw == lastSeenDiskRaw { return }
        lastSeenDiskRaw = raw
        refresh()
    }

    // MARK: Capture journal (own-capture insurance)

    /// "iPhone" or "iPad"; written into every entry captured on this device.
    static let deviceName: String = UIDevice.current.model

    /// Captures made here that have not yet been confirmed present in a loaded
    /// inbox. If an iCloud race drops one, the next refresh folds it back in.
    private static let journalKey = "ledge.captureJournal"

    private func journalItems() -> [[String: String]] {
        UserDefaults.standard.array(forKey: Self.journalKey) as? [[String: String]] ?? []
    }

    private func journalAdd(text: String, at date: Date) {
        var items = journalItems()
        items.append(["stamp": LedgeFormat.spoolFormatter.string(from: date), "text": text])
        UserDefaults.standard.set(items, forKey: Self.journalKey)
    }

    /// Fold unconfirmed own captures back into a freshly loaded inbox. Items
    /// seen on disk are confirmed and leave the journal; items older than a
    /// week are let go. Returns the number folded back in.
    private func reconcileJournal(into loaded: inout Inbox) -> Int {
        let items = journalItems()
        guard !items.isEmpty else { return 0 }
        let present = Set(loaded.allEntries().map { pair in
            LedgeFormat.spoolFormatter.string(from: pair.entry.timestamp) + "|" + pair.entry.text
        })
        var folded = 0
        var remaining: [[String: String]] = []
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for item in items {
            guard let stampString = item["stamp"], let text = item["text"],
                  let stamp = LedgeFormat.spoolFormatter.date(from: stampString) else { continue }
            if present.contains(stampString + "|" + text) { continue }
            if stamp < cutoff { continue }
            folded += loaded.fold([(date: stamp, text: text, device: Self.deviceName)])
            remaining.append(item)
        }
        UserDefaults.standard.set(remaining, forKey: Self.journalKey)
        return folded
    }

    // MARK: Entry editing

    /// Replace the text of one entry, found by timestamp plus old text.
    /// An empty replacement removes the entry (nothing else is touched).
    func updateEntry(original: Entry, newText: String) {
        let cleaned = LedgeFormat.trimEdges(newText)
        guard cleaned != original.text else { return }
        guard let store else { return }
        var updated = inbox
        for dayIndex in updated.days.indices {
            guard let entryIndex = updated.days[dayIndex].entries.firstIndex(where: {
                $0.timestamp == original.timestamp && $0.text == original.text
            }) else { continue }
            if cleaned.isEmpty {
                updated.days[dayIndex].entries.remove(at: entryIndex)
                updated.removeEmptyEntries()
            } else {
                updated.days[dayIndex].entries[entryIndex].text = cleaned
            }
            do {
                try store.saveInbox(updated)
                inbox = updated
            } catch {
                notice = "That edit could not be saved just now. Try again in a moment."
            }
            return
        }
    }

    /// Toggle a checkbox line inside an entry, found by timestamp plus text.
    func toggleCheckbox(in entry: Entry, lineIndex: Int) {
        guard let store else { return }
        var updated = inbox
        for dayIndex in updated.days.indices {
            guard let entryIndex = updated.days[dayIndex].entries.firstIndex(where: {
                $0.timestamp == entry.timestamp && $0.text == entry.text
            }) else { continue }
            var lines = updated.days[dayIndex].entries[entryIndex].text.components(separatedBy: "\n")
            guard lines.indices.contains(lineIndex) else { return }
            lines[lineIndex] = Self.toggledCheckboxLine(lines[lineIndex])
            updated.days[dayIndex].entries[entryIndex].text = lines.joined(separator: "\n")
            do {
                try store.saveInbox(updated)
                inbox = updated
            } catch {
                notice = "That change could not be saved just now. Try again in a moment."
            }
            return
        }
    }

    /// `- [ ]` becomes `- [x]` and back, leading whitespace preserved.
    static func toggledCheckboxLine(_ line: String) -> String {
        if let range = line.range(of: "[ ]") {
            return line.replacingCharacters(in: range, with: "[x]")
        }
        if let range = line.range(of: "[x]") {
            return line.replacingCharacters(in: range, with: "[ ]")
        }
        if let range = line.range(of: "[X]") {
            return line.replacingCharacters(in: range, with: "[ ]")
        }
        return line
    }

    /// A closed checkbox line, the mirror of LedgeStore.isOpenCheckbox.
    static func isClosedCheckbox(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("* [x]")
            || trimmed.hasPrefix("- [X]") || trimmed.hasPrefix("* [X]")
    }

    // MARK: Send anywhere (A6, capped on purpose)

    /// One-shot handoff to Apple Reminders. Asks for access on first use;
    /// nothing is read back, nothing recurs. Calm by design.
    func sendToReminders(_ entry: Entry) {
        let eventStore = EKEventStore()
        let finish: (Bool) -> Void = { [weak self] granted in
            DispatchQueue.main.async {
                guard granted else {
                    self?.notice = "Ledge needs Reminders access for that. You can allow it in Settings."
                    return
                }
                let reminder = EKReminder(eventStore: eventStore)
                let firstLine = entry.text.components(separatedBy: "\n").first ?? entry.text
                reminder.title = String(firstLine.prefix(120))
                reminder.notes = entry.text + "\n\nfrom Ledge"
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
                do {
                    try eventStore.save(reminder, commit: true)
                    self?.notice = "Sent to Reminders."
                } catch {
                    self?.notice = "Reminders did not accept that just now. Try again in a moment."
                }
            }
        }
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToReminders { granted, _ in finish(granted) }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, _ in finish(granted) }
        }
    }

    // MARK: Search, loops, notes

    func search(_ query: String) -> [SearchHit] {
        guard let store else { return [] }
        return store.search(query, inbox: inbox)
    }

    func openLoops() -> [OpenLoop] {
        guard let store else { return [] }
        return store.openLoops(inbox: inbox)
    }

    func listNotes() -> [NoteMeta] {
        guard let store else { return [] }
        return (try? store.listNotes()) ?? []
    }

    func createNote(title: String) -> URL? {
        guard let store else { return nil }
        do {
            return try store.createNote(title: title)
        } catch {
            notice = "That note could not be created just now. Try again in a moment."
            return nil
        }
    }

    func readNote(at url: URL) -> String {
        guard let store else { return "" }
        do {
            return try store.readString(url) ?? ""
        } catch {
            notice = "That note is not readable right now. If it lives in iCloud, give it a moment to download."
            return ""
        }
    }

    func writeNote(_ text: String, to url: URL) {
        guard let store else { return }
        do {
            try store.saveNote(text, to: url)
        } catch {
            notice = "That note could not be saved just now. Your text stays here; try again in a moment."
        }
    }
}

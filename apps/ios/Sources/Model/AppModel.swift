// The app model: folder bookmark, LedgeStore, inbox state, calm notices,
// and (since 2026-09-03) an honest account of whether sync is alive.
// Built by Claude (Anthropic).

import Foundation
import SwiftUI
import UIKit
import EventKit
import LedgeCore

/// Why the folder cannot be trusted right now. Three causes, three messages,
/// three different fixes. Before this existed every failure said "tap the
/// folder icon and pick it again", including the ones where re-picking could
/// not help (incident brief 2026-09-03, failure mode K).
enum SyncFault: Equatable {
    /// The bookmark resolves but grants nothing. Every iOS reinstall does this.
    case grantDead
    /// iCloud has a newer inbox.md than the bytes on this device.
    case notDownloaded(percent: Double?)
    /// Anything else, with the underlying error so it can be acted on.
    case other(String)

    var message: String {
        switch self {
        case .grantDead:
            return "Ledge's access to your folder ended. This happens after a reinstall. Tap Re-pick and choose iCloud Drive > Ledge."
        case .notDownloaded(let percent):
            if let percent, percent > 0, percent < 100 {
                return "Your inbox has not finished downloading from iCloud (\(Int(percent))%)."
            }
            return "Your inbox has not finished downloading from iCloud."
        case .other(let detail):
            return "Ledge could not read your folder: " + detail
        }
    }

    var actionTitle: String {
        switch self {
        case .grantDead: return "Re-pick"
        case .notDownloaded: return "Download now"
        case .other: return "Try again"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {

    /// Parsed inbox, the single source of truth for the UI.
    @Published private(set) var inbox = Inbox()

    /// Calm amber banner text for transient events. Nil when everything is fine.
    @Published var notice: String?

    /// The persistent sync fault, if any. Drives the blocking card with its
    /// one-tap fix. Nil is the healthy, invisible case.
    @Published private(set) var fault: SyncFault?

    /// Muted capture-trust line: captures waiting outside the inbox (the spool
    /// or the local pending queue) after a drain attempt. Nil when everything
    /// has landed, which is the healthy, invisible case.
    @Published private(set) var waitingLine: String?

    /// Muted sync-health line: "last seen from MacBook M4: 9 hours ago" when
    /// another device's heartbeat is older than the threshold. Nil when healthy.
    @Published private(set) var peerLine: String?

    /// The outcome of the last explicit refresh, shown briefly under the
    /// capture bar so pressing the button is informative, not an act of faith.
    @Published private(set) var refreshOutcome: String?

    /// True while refreshNow() is working (spins the toolbar button).
    @Published private(set) var refreshing = false

    /// True when a folder bookmark exists (drives setup vs inbox screen).
    @Published private(set) var hasFolder: Bool

    /// True when the bookmark resolved, the grant was probed, and the store is
    /// usable right now. Never set from "a read did not throw" alone.
    @Published private(set) var isConnected = false

    private(set) var store: LedgeStore?
    private var rootURL: URL?
    private var settings = LedgeSettings.defaults

    static let appVersion: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"

    init() {
        hasFolder = UserDefaults.standard.data(forKey: SpoolWriter.bookmarkKey) != nil
        restore()
    }

    // MARK: Folder connection

    /// Called from the folder picker. Bookmarks the folder and opens it.
    func connectFolder(url: URL) {
        // The picker coordinator already started scoped access for this URL;
        // starting it a second time leaked one access per connect (audit 2026-09-02).
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
            fault = .grantDead
            return
        }
        // A reinstall can invalidate the security scope even when the bookmark
        // still resolves to a URL. Treat failed access as disconnected instead
        // of pressing on with a folder we cannot actually read (2026-08-19).
        guard url.startAccessingSecurityScopedResource() else {
            isConnected = false
            fault = .grantDead
            return
        }
        if stale, let fresh = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(fresh, forKey: SpoolWriter.bookmarkKey)
        }
        openRoot(url)
    }

    /// The root whose security scope this model currently holds. iOS caps
    /// concurrent scoped accesses per process; every openRoot used to start a
    /// new one and never stop the old, so a few reconnects exhausted the cap
    /// and the app showed "lost access" until relaunch.
    private var scopedRoot: URL?

    private func openRoot(_ url: URL) {
        if let previous = scopedRoot, previous != url {
            previous.stopAccessingSecurityScopedResource()
        }
        scopedRoot = url
        rootURL = url
        let store = LedgeStore(root: url)
        self.store = store
        do {
            try store.bootstrap()
            // M1: startAccessingSecurityScopedResource() returning true is not
            // proof of anything after a reinstall. Prove the grant by writing.
            try store.probeWriteAccess()
            settings = LedgeSettings.load(from: store.settingsURL)
            isConnected = true
            fault = nil
            writeHeartbeat(force: true)
            flushPending()
            refresh()
        } catch {
            isConnected = false
            fault = classify(error, assumeGrant: true)
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
        writeHeartbeat(force: true)
    }

    /// Reload the inbox from disk, drain the spool, age old days, save if changed.
    /// Sets or clears `fault` from evidence: a probe, a download state, or the
    /// classified error. Never claims health because a read merely returned.
    @discardableResult
    func refresh() -> Int {
        guard let store else { return 0 }
        var folded = 0
        do {
            var loaded = try store.loadInbox()
            let repairs = store.lastLoadRepairs
            let drained = try store.drainSpool(into: &loaded)
            let aged = try store.age(&loaded, olderThanDays: settings.agingDays)
            let journaled = reconcileJournal(into: &loaded)
            if drained + aged + journaled > 0 {
                try store.saveInbox(loaded)
            }
            folded = drained + journaled
            inbox = loaded
            isConnected = true
            // Stamp what this device now holds; no-op unless the bytes changed.
            writeHeartbeat()
            // M6: a read that succeeded on stale bytes is not health. Ask iCloud.
            if let state = store.downloadState(of: store.inboxURL), state.status != .current {
                fault = .notDownloaded(percent: state.percent)
            } else {
                fault = nil
            }
            // Say what was healed, once; clear it when the next load is clean.
            if !repairs.isEmpty {
                notice = "Repaired the inbox file: " + repairs.joined(separator: "; ") + "."
            } else if notice?.hasPrefix("Repaired the inbox file") == true {
                notice = nil
            }
        } catch {
            // Reads failing means we are NOT connected, whatever we believed
            // before. Leaving isConnected true here hid the re-pick path for
            // an entire morning (2026-08-19).
            isConnected = false
            fault = classify(error, assumeGrant: false)
        }
        updateWaitingLine()
        updatePeerLine()
        return folded
    }

    /// M2: the explicit Refresh button. Reconnects if needed, forces a real
    /// download wait when iCloud says the copy is stale, reads, drains,
    /// flushes, and always reports an outcome, including "nothing changed".
    func refreshNow() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let started = Date()

        if store == nil || !isConnected {
            restore()
            if !isConnected {
                refreshOutcome = fault?.message ?? "Not connected to a folder."
                scheduleOutcomeClear()
                return
            }
        }
        guard let store else { return }

        // Re-probe the grant on every explicit refresh: it is the one moment
        // the user is looking, and the probe is a 0-byte write.
        do {
            try store.probeWriteAccess()
        } catch {
            isConnected = false
            fault = .grantDead
            refreshOutcome = SyncFault.grantDead.message
            scheduleOutcomeClear()
            return
        }

        // Download with a real timeout, off the main actor.
        let inboxURL = store.inboxURL
        let state = await Task.detached(priority: .userInitiated) {
            store.downloadAndWait(inboxURL, timeout: 30)
        }.value

        flushPending()
        let folded = refresh()
        writeHeartbeat(force: true)

        if let state, state.status != .current {
            fault = .notDownloaded(percent: state.percent)
            refreshOutcome = "Could not download your inbox from iCloud in 30 seconds."
        } else if let fault {
            refreshOutcome = fault.message
        } else if folded > 0 {
            refreshOutcome = folded == 1 ? "1 capture folded in." : "\(folded) captures folded in."
        } else if !store.lastLoadRepairs.isEmpty {
            refreshOutcome = "Repaired: " + store.lastLoadRepairs.joined(separator: "; ") + "."
        } else {
            let elapsed = Date().timeIntervalSince(started)
            refreshOutcome = elapsed < 1.5 ? "Up to date, just now." : "Up to date, checked in \(Int(elapsed.rounded())) s."
        }
        scheduleOutcomeClear()
    }

    /// The fault card's one button. Each cause gets the fix that actually helps.
    /// Returns true when the caller should present the folder picker.
    func performFaultAction() async -> Bool {
        switch fault {
        case .grantDead:
            return true
        case .notDownloaded, .other, .none:
            await refreshNow()
            return false
        }
    }

    private var outcomeClear: Task<Void, Never>?

    private func scheduleOutcomeClear() {
        outcomeClear?.cancel()
        outcomeClear = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            refreshOutcome = nil
        }
    }

    /// M3: the cause discriminator. `assumeGrant` is true when the failure came
    /// from bootstrap or the probe, where a permission error can only mean the
    /// grant is dead.
    private func classify(_ error: Error, assumeGrant: Bool) -> SyncFault {
        if let storeError = error as? LedgeStoreError, case .notDownloaded = storeError {
            let percent = store.flatMap { $0.downloadState(of: $0.inboxURL)?.percent }
            return .notDownloaded(percent: percent)
        }
        let ns = error as NSError
        var codes: [(String, Int)] = [(ns.domain, ns.code)]
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            codes.append((underlying.domain, underlying.code))
        }
        for (domain, code) in codes {
            if domain == NSCocoaErrorDomain,
               [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(code) {
                return .grantDead
            }
            if domain == NSPOSIXErrorDomain, code == Int(EPERM) || code == Int(EACCES) {
                return .grantDead
            }
        }
        if assumeGrant, ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteUnknownError {
            return .grantDead
        }
        return .other(ns.localizedDescription)
    }

    /// Recount what is waiting outside the inbox. Called after every drain or
    /// queue attempt so the muted line tracks reality, not hope. Pass the
    /// spool content when the caller already read it this tick.
    private func updateWaitingLine(spoolRaw: String? = nil) {
        var status = Spool.status(SpoolWriter.pendingContents() ?? "", fallbackDate: Date())
        if let store, isConnected {
            let raw = spoolRaw ?? (((try? store.readString(store.spoolURL)) ?? nil) ?? "")
            let fallback = store.modificationDate(of: store.spoolURL) ?? Date()
            status = status.merged(with: Spool.status(raw, fallbackDate: fallback))
        }
        let line = status.waitingLine()
        if line != waitingLine { waitingLine = line }
    }

    // MARK: Sync health (M4)

    private var lastHeartbeatWrite: Date = .distantPast
    private var lastHeartbeatDigest: String?

    /// Write this device's heartbeat: on launch, on activation, on capture,
    /// whenever the inbox bytes it holds have changed, and otherwise at most
    /// every five minutes while foregrounded. The digest is what lets another
    /// device (or deploy.sh) prove this one is looking at the same inbox.
    /// A failed write is a real signal and surfaces through the fault path.
    private func writeHeartbeat(force: Bool = false) {
        guard let store, isConnected else { return }
        let now = Date()
        let digest = store.inboxDigest()
        let due = now.timeIntervalSince(lastHeartbeatWrite) >= 300
        guard force || due || digest != lastHeartbeatDigest else { return }
        do {
            try store.writeHeartbeat(device: Self.deviceName, version: Self.appVersion, platform: "iOS", now: now)
            lastHeartbeatWrite = now
            lastHeartbeatDigest = digest
        } catch {
            isConnected = false
            fault = classify(error, assumeGrant: true)
        }
    }

    private func updatePeerLine() {
        guard let store, isConnected else {
            if peerLine != nil { peerLine = nil }
            return
        }
        let line = LedgeStore.peerLine(from: store.readHeartbeats(), selfDevice: Self.deviceName)
        if line != peerLine { peerLine = line }
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
            writeHeartbeat(force: true)
        } catch {
            SpoolWriter.appendToPending(Spool.line(for: trimmed, at: now, device: Self.deviceName))
            notice = "Captured to the local queue. Ledge will file it when the folder is reachable."
            fault = classify(error, assumeGrant: false)
            updateWaitingLine()
        }
    }

    /// Capture before any folder is connected: queue locally, flush later.
    func queueWhenDisconnected(text: String, at date: Date = Date()) {
        let trimmed = LedgeFormat.trimEdges(text)
        guard !trimmed.isEmpty else { return }
        SpoolWriter.appendToPending(Spool.line(for: trimmed, at: date, device: Self.deviceName))
        notice = "Captured. Ledge will file it once your folder is connected."
        updateWaitingLine()
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
            // The waiting line keeps counting these; a transient notice here
            // was wiped by the next refresh two seconds later (brief, item 11).
            fault = classify(error, assumeGrant: false)
        }
        updateWaitingLine()
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
        // Out-of-app captures (Back Tap, Lock Screen, share sheet, watch relay)
        // land in the spool or the local pending queue, not the inbox, so the
        // heartbeat watches all three. readString also nudges iCloud downloads.
        if SpoolWriter.pendingContents() != nil { flushPending() }
        let spool: String
        let raw: String
        do {
            // A thrown read used to collapse into "" and match the initial
            // lastSeenDiskRaw, so the tick returned early forever while the
            // folder was unreadable (brief, section 5 item 1). Now it routes
            // through refresh(), which classifies and reports.
            spool = try store.readString(store.spoolURL) ?? ""
            raw = try store.readString(store.inboxURL) ?? ""
        } catch {
            refresh()
            return
        }
        writeHeartbeat()
        if raw == lastSeenDiskRaw && LedgeFormat.trimEdges(spool).isEmpty {
            updateWaitingLine(spoolRaw: spool)
            // Cheap and honest: even when bytes did not change, iCloud may
            // know about a newer version we do not have yet.
            if fault == nil, let state = store.downloadState(of: store.inboxURL), state.status != .current {
                fault = .notDownloaded(percent: state.percent)
            } else if case .notDownloaded = fault, let state = store.downloadState(of: store.inboxURL), state.status == .current {
                fault = nil
            }
            return
        }
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
        // Presence is keyed on minute stamp plus device, not on the exact text:
        // an own capture that was edited on the Mac is still that capture, and
        // matching on text re-added the original as a duplicate for seven days.
        // A capture deleted elsewhere is recognised the same way: if the inbox
        // on disk is newer than the capture by two minutes and the entry is
        // absent, another device already saw and removed it (audit 2026-09-02).
        let present = Set(loaded.allEntries().map { pair in
            LedgeFormat.spoolFormatter.string(from: pair.entry.timestamp) + "|" + (pair.entry.device ?? "")
        })
        let inboxStamp = store.flatMap { $0.modificationDate(of: $0.inboxURL) }
        var folded = 0
        var remaining: [[String: String]] = []
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for item in items {
            guard let stampString = item["stamp"], let text = item["text"],
                  let stamp = LedgeFormat.spoolFormatter.date(from: stampString) else { continue }
            if present.contains(stampString + "|" + Self.deviceName) { continue }
            if let inboxStamp, inboxStamp > stamp.addingTimeInterval(120) { continue }
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

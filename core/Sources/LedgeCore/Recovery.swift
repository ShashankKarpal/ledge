// The Recovery report: everything a person needs to see when sync feels
// wrong, gathered from what is already on disk, and NOTHING they typed.
//
// Two rules, both enforced by tests:
//
// 1. Observational. Gathering a report reads local files and local iCloud
//    metadata only. It never requests a download, never writes into the
//    synced folder, never touches the transport it is describing. The one
//    exception is the caller's explicit "retry filing" action, which is the
//    ordinary drain-and-commit path and not part of this file.
// 2. Content-free. The diagnostic text is the artefact designed to be pasted
//    into an issue or a chat, so it carries counts, stamps, digests, device
//    labels and versions, and never a capture's text. The unaccounted list
//    keeps stamps and devices; the text stays in capture-log.jsonl where it
//    belongs. `testDiagnosticReportHoldsNoCaptureText` plants phrases in every
//    place text can live and asserts none of them survive.
//
// Shared in LedgeCore so the Mac and iOS screens render one truth.
// Built by Claude (Anthropic).

import Foundation

public struct RecoveryReport: Equatable {
    /// One stamp-plus-device line for a capture the write-ahead log holds but
    /// the inbox does not. Deliberately has no text field.
    public struct Unaccounted: Equatable {
        public var at: Date
        public var device: String
        public init(at: Date, device: String) {
            self.at = at
            self.device = device
        }
    }

    public struct HeartbeatRow: Equatable {
        public var device: String
        public var at: Date
        public var version: String
        public var platform: String
        public var digest: String?
        public var isSelf: Bool
        public init(device: String, at: Date, version: String, platform: String, digest: String?, isSelf: Bool) {
            self.device = device
            self.at = at
            self.version = version
            self.platform = platform
            self.digest = digest
            self.isSelf = isSelf
        }
    }

    public struct Backups: Equatable {
        public var count: Int
        public var newest: Date?
        public var bytes: Int
        public init(count: Int, newest: Date?, bytes: Int) {
            self.count = count
            self.newest = newest
            self.bytes = bytes
        }
    }

    public var generatedAt: Date
    public var appVersion: String
    public var platform: String
    public var selfDevice: String

    /// The notes folder, shown with the home directory abbreviated so the
    /// report never carries an account name.
    public var folderDisplayPath: String
    public var folderReachable: Bool
    public var inboxExists: Bool
    public var inboxBytes: Int?
    public var inboxModified: Date?
    public var inboxDigest: String?
    public var inboxDownload: LedgeStore.DownloadState?
    public var inboxEntries: Int?
    public var inboxDays: Int?
    public var lastLoadRepairs: [String]

    public var heartbeats: [HeartbeatRow]
    public var syncHealthLine: String?

    public var spool: SpoolStatus
    public var spoolBytes: Int
    public var unaccounted: [Unaccounted]
    public var captureLogEntries: Int
    public var conflictVersions: Int
    public var incidents: [SyncIncident]
    public var incidentSummary30d: IncidentLog.Summary
    public var lastInstall: Date?
    public var editorJournalBytes: Int?
    public var backups: Backups?

    // MARK: Gathering

    /// Read-only sources a report is built from. Every URL is optional so a
    /// platform without that file passes nil rather than a fake path.
    public struct Sources {
        public var store: LedgeStore
        public var captureLog: CaptureLog?
        public var editorJournalURL: URL?
        public var backups: Backups?
        public var selfDevice: String
        public var appVersion: String
        public var platform: String
        public var syncHealthLine: String?
        public init(
            store: LedgeStore,
            captureLog: CaptureLog? = nil,
            editorJournalURL: URL? = nil,
            backups: Backups? = nil,
            selfDevice: String,
            appVersion: String,
            platform: String,
            syncHealthLine: String? = nil
        ) {
            self.store = store
            self.captureLog = captureLog
            self.editorJournalURL = editorJournalURL
            self.backups = backups
            self.selfDevice = selfDevice
            self.appVersion = appVersion
            self.platform = platform
            self.syncHealthLine = syncHealthLine
        }
    }

    public static func gather(_ s: Sources, now: Date = Date()) -> RecoveryReport {
        let fm = FileManager.default
        let store = s.store

        let reachable = fm.isReadableFile(atPath: store.root.path)
        let inboxAttrs = try? fm.attributesOfItem(atPath: store.inboxURL.path)
        let inboxExists = inboxAttrs != nil
        let inboxBytes = inboxAttrs?[.size] as? Int
        let inboxModified = inboxAttrs?[.modificationDate] as? Date

        // Parse the LOCAL bytes without triggering a download: loadInbox may
        // wait on iCloud, which is a transport request this report must not
        // make. Data(contentsOf:) on a placeholder simply fails, and the
        // download row says why.
        var entries: Int?
        var days: Int?
        var repairs: [String] = []
        if let data = try? Data(contentsOf: store.inboxURL) {
            let parsed = Inbox.parseReporting(String(decoding: data, as: UTF8.self))
            entries = parsed.inbox.allEntries().count
            days = parsed.inbox.days.count
            repairs = parsed.repairs
        }

        let beats = store.readHeartbeats().map { beat in
            HeartbeatRow(
                device: beat.device,
                at: beat.at,
                version: beat.version,
                platform: beat.platform,
                digest: beat.inboxDigest,
                isSelf: beat.device == s.selfDevice
            )
        }

        var spoolStatus = SpoolStatus.empty
        var spoolBytes = 0
        if let data = try? Data(contentsOf: store.spoolURL) {
            spoolBytes = data.count
            spoolStatus = Spool.status(String(decoding: data, as: UTF8.self), fallbackDate: now)
        }

        var unaccounted: [Unaccounted] = []
        var logged = 0
        if let log = s.captureLog {
            logged = log.entries().filter { $0.intent != "confirm" }.count
            if let data = try? Data(contentsOf: store.inboxURL) {
                let inbox = Inbox.parse(String(decoding: data, as: UTF8.self))
                unaccounted = log.unrecovered(comparedTo: inbox, now: now)
                    .map { Unaccounted(at: $0.at, device: $0.device) }
            }
        }

        var conflicts = 0
        #if os(macOS) || os(iOS)
        conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: store.inboxURL)?.count ?? 0
        #endif

        let incidents = store.readIncidents()
        let summary = IncidentLog.summary(of: incidents, since: now.addingTimeInterval(-30 * 86400), now: now)

        var lastInstall: Date?
        if let seconds = store.secondsSinceLastInstall(now: now) {
            lastInstall = now.addingTimeInterval(-seconds)
        }

        var journalBytes: Int?
        if let url = s.editorJournalURL,
           let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int {
            journalBytes = size
        }

        return RecoveryReport(
            generatedAt: now,
            appVersion: s.appVersion,
            platform: s.platform,
            selfDevice: s.selfDevice,
            folderDisplayPath: Self.abbreviateHome(store.root.path),
            folderReachable: reachable,
            inboxExists: inboxExists,
            inboxBytes: inboxBytes,
            inboxModified: inboxModified,
            inboxDigest: store.inboxDigest(),
            inboxDownload: store.downloadState(of: store.inboxURL),
            inboxEntries: entries,
            inboxDays: days,
            lastLoadRepairs: repairs,
            heartbeats: beats,
            syncHealthLine: s.syncHealthLine,
            spool: spoolStatus,
            spoolBytes: spoolBytes,
            unaccounted: unaccounted,
            captureLogEntries: logged,
            conflictVersions: conflicts,
            incidents: incidents,
            incidentSummary30d: summary,
            lastInstall: lastInstall,
            editorJournalBytes: journalBytes,
            backups: s.backups
        )
    }

    /// `/Users/name/Library/...` becomes `~/Library/...`. The report is meant
    /// to be pasted places; an account name is not part of a sync diagnosis.
    public static func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    // MARK: Wording

    /// One line per fact, the same wording the screens show, so the text a
    /// person pastes is exactly what they saw. No capture text can enter this
    /// function: it has no access to any, by construction.
    public func diagnosticText() -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        func stamp(_ d: Date?) -> String { d.map { f.string(from: $0) } ?? "never" }
        func age(_ d: Date?) -> String {
            guard let d else { return "never" }
            return LedgeFormat.roughAge(generatedAt.timeIntervalSince(d))
        }
        var out: [String] = []
        out.append("Ledge recovery report")
        out.append("generated: \(stamp(generatedAt))")
        out.append("app: \(appVersion) on \(platform), this device: \(selfDevice)")
        out.append("")
        out.append("FOLDER")
        out.append("path: \(folderDisplayPath)")
        out.append("reachable: \(folderReachable ? "yes" : "NO")")
        if inboxExists {
            out.append("inbox.md: \(inboxBytes ?? 0) bytes, modified \(stamp(inboxModified)) (\(age(inboxModified)))")
        } else {
            out.append("inbox.md: MISSING")
        }
        out.append("inbox digest: \(inboxDigest ?? "unreadable")")
        out.append("inbox download: \(Self.describe(inboxDownload))")
        if let entries = inboxEntries, let days = inboxDays {
            out.append("inbox parsed: \(entries) entries across \(days) days")
        } else {
            out.append("inbox parsed: not readable locally")
        }
        if !lastLoadRepairs.isEmpty {
            out.append("repairs the reader would apply: \(lastLoadRepairs.count)")
        }
        out.append("")
        out.append("SYNC")
        out.append("health line: \(syncHealthLine ?? "healthy (no line)")")
        if heartbeats.isEmpty {
            out.append("heartbeats: none")
        }
        for beat in heartbeats {
            let agree: String
            if let d = beat.digest, let mine = inboxDigest {
                agree = d == mine ? "same bytes" : "different bytes"
            } else {
                agree = "no digest"
            }
            let who = beat.isSelf ? "\(beat.device) (this device)" : beat.device
            out.append("heartbeat \(who): \(age(beat.at)), \(beat.platform) \(beat.version), \(agree)")
        }
        out.append("conflict versions unresolved: \(conflictVersions)")
        out.append("last install on this device: \(stamp(lastInstall)) (\(age(lastInstall)))")
        out.append("")
        out.append("CAPTURES")
        out.append("spool (capture/drop.md): \(spool.count) waiting, \(spoolBytes) bytes"
            + (spool.oldest.map { ", oldest \(age($0))" } ?? ""))
        out.append("capture log on this device: \(captureLogEntries) recorded")
        if unaccounted.isEmpty {
            out.append("unaccounted captures: 0")
        } else {
            out.append("unaccounted captures: \(unaccounted.count)")
            for item in unaccounted.prefix(20) {
                out.append("  \(LedgeFormat.spoolFormatter.string(from: item.at)) from \(item.device)")
            }
        }
        if let bytes = editorJournalBytes {
            out.append("editor recovery journal: present, \(bytes) bytes (text not yet saved to the inbox)")
        } else {
            out.append("editor recovery journal: none")
        }
        out.append("")
        out.append("INCIDENTS (last 30 days)")
        out.append("count: \(incidentSummary30d.count), total \(LedgeFormat.roughDuration(incidentSummary30d.totalDuration)), longest \(LedgeFormat.roughDuration(incidentSummary30d.longest)), within an hour of an install: \(incidentSummary30d.withinAnHourOfInstall), ongoing: \(incidentSummary30d.ongoing)")
        for incident in incidents.suffix(10).reversed() {
            let end = incident.endedAt.map { stamp($0) } ?? "ongoing"
            out.append("  \(incident.kind.rawValue) seen by \(incident.observer) vs \(incident.peer ?? "?"): \(stamp(incident.startedAt)) to \(end), app \(incident.version)")
        }
        out.append("")
        out.append("LOCAL SAFETY COPIES")
        if let b = backups, b.count > 0 {
            out.append("backups: \(b.count), newest \(stamp(b.newest)) (\(age(b.newest))), \(b.bytes) bytes")
        } else {
            out.append("backups: none yet")
        }
        return out.joined(separator: "\n") + "\n"
    }

    public static func describe(_ state: LedgeStore.DownloadState?) -> String {
        guard let state else { return "local file (not an iCloud item)" }
        switch state.status {
        case .current: return "current"
        case .stale: return state.isDownloading ? "newer version downloading" : "newer version exists, not downloaded"
        case .notDownloaded: return state.isDownloading ? "downloading" : "NOT DOWNLOADED (placeholder only)"
        }
    }
}

// The incident log: a small, durable, content-free record of when sync was
// observably broken, so the question "how often does this actually happen"
// has an answer that does not depend on anyone remembering.
//
// Why this exists. On 2026-09-03 the decision of whether to build a second
// sync transport came down to two remembered stalls, and neither review could
// check that number, because the evidence was heartbeat files that overwrite
// themselves and a disagreement clock that clears on recovery. A decision that
// expensive deserves counted evidence.
//
// Privacy and size are deliberate. No capture text, no file contents, no paths
// beyond a device label the owner chose. One line per incident, JSON, capped
// at 200 lines. It lives in .ledge/incidents.log inside the shared folder so
// both devices contribute to one record, and it is append-only in normal use.
//
// Built by Claude (Anthropic).

import Foundation

/// One observed period during which this device could not agree with a peer,
/// or could not reach the folder at all.
public struct SyncIncident: Codable, Equatable {
    public enum Kind: String, Codable {
        /// A peer was alive and reachable but held different bytes than we did.
        case disagreement
        /// The folder itself could not be read or written from this device.
        case folderUnreachable
        /// iCloud reported the inbox as not current for an extended period.
        case notDownloaded
    }

    public var kind: Kind
    /// The device that noticed, not the device at fault.
    public var observer: String
    public var startedAt: Date
    public var endedAt: Date?
    /// Which peer the disagreement was with, when there is one.
    public var peer: String?
    /// App version of the observer, so a bad build can be spotted.
    public var version: String
    /// Seconds between the newest install this device knows about and the
    /// incident starting. Nil when no install has been recorded. This is the
    /// number that settles whether reinstalls really are the trigger.
    public var secondsAfterInstall: TimeInterval?

    public var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    public init(
        kind: Kind,
        observer: String,
        startedAt: Date,
        endedAt: Date? = nil,
        peer: String? = nil,
        version: String,
        secondsAfterInstall: TimeInterval? = nil
    ) {
        self.kind = kind
        self.observer = observer
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.peer = peer
        self.version = version
        self.secondsAfterInstall = secondsAfterInstall
    }
}

public enum IncidentLog {
    /// Hard cap. Old lines fall off the front; this file must never become a
    /// thing that itself needs managing.
    public static let maxEntries = 200

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func parse(_ raw: String) -> [SyncIncident] {
        raw.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
            return try? decoder.decode(SyncIncident.self, from: data)
        }
    }

    public static func serialize(_ incidents: [SyncIncident]) -> String {
        let capped = incidents.suffix(maxEntries)
        let lines = capped.compactMap { incident -> String? in
            guard let data = try? encoder.encode(incident) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    /// Fold a new observation into an existing log. An ongoing incident of the
    /// same kind, from the same observer about the same peer, is EXTENDED
    /// rather than duplicated; that is what keeps a two hour stall as one
    /// incident instead of forty.
    public static func record(
        _ incident: SyncIncident,
        into incidents: [SyncIncident]
    ) -> [SyncIncident] {
        var out = incidents
        if let index = out.lastIndex(where: {
            $0.kind == incident.kind
                && $0.observer == incident.observer
                && $0.peer == incident.peer
                && $0.endedAt == nil
        }) {
            out[index].endedAt = incident.endedAt
            return out
        }
        out.append(incident)
        return out
    }

    /// Close any open incident matching kind, observer and peer. Called when
    /// the condition clears, which is the only way an incident gets a duration.
    public static func close(
        kind: SyncIncident.Kind,
        observer: String,
        peer: String?,
        at date: Date,
        in incidents: [SyncIncident]
    ) -> [SyncIncident] {
        var out = incidents
        for index in out.indices
        where out[index].kind == kind
            && out[index].observer == observer
            && out[index].peer == peer
            && out[index].endedAt == nil {
            out[index].endedAt = date
        }
        return out
    }

    /// The summary the owner and the roadmap both need: how many verified
    /// stalls, how long in total, and how many of them began within an hour of
    /// an install. These are exactly the numbers the relay decision turns on.
    public struct Summary: Equatable {
        public var count: Int
        public var totalDuration: TimeInterval
        public var longest: TimeInterval
        public var withinAnHourOfInstall: Int
        public var ongoing: Int

        public var line: String? {
            guard count > 0 else { return nil }
            let noun = count == 1 ? "1 sync incident" : "\(count) sync incidents"
            return noun + " in the window, " + LedgeFormat.roughDuration(totalDuration) + " total"
        }
    }

    public static func summary(
        of incidents: [SyncIncident],
        since: Date,
        now: Date = Date()
    ) -> Summary {
        let window = incidents.filter { $0.startedAt >= since }
        var total: TimeInterval = 0
        var longest: TimeInterval = 0
        var nearInstall = 0
        var ongoing = 0
        for incident in window {
            let end = incident.endedAt ?? now
            let duration = max(0, end.timeIntervalSince(incident.startedAt))
            total += duration
            longest = max(longest, duration)
            if incident.endedAt == nil { ongoing += 1 }
            if let after = incident.secondsAfterInstall, after <= 3600 { nearInstall += 1 }
        }
        return Summary(
            count: window.count,
            totalDuration: total,
            longest: longest,
            withinAnHourOfInstall: nearInstall,
            ongoing: ongoing
        )
    }
}

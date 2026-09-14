// Recovery: the screen to open when sync feels wrong. Observational first.
//
// Everything here is read from what is already on disk through
// RecoveryReport (LedgeCore), which is content-free by construction and
// tested to stay that way. The window reads on open, on Refresh, and every
// 20 seconds while it is visible; never while closed, so it is not a load on
// the folder it describes. The only actions are safe ones: retry filing (the
// ordinary drain path), reveal the folder, reveal the local safety copies,
// copy the diagnostic report. There is no restore here yet; when it comes it
// writes into a NEW folder, never over the live one.
// Built by Claude (Anthropic).

import AppKit
import SwiftUI
#if canImport(LedgeCore)
import LedgeCore
#endif

/// What the window needs from the app: how to build a report, and the safe
/// actions. Injected so the view never reaches into AppDelegate.
struct RecoveryActions {
    var gather: () -> RecoveryReport
    /// Drain the spool and fold conflicts through the ordinary save path.
    /// Returns a one-line outcome for the screen.
    var retryFiling: () -> String
    var revealFolder: () -> Void
    var revealSafetyCopies: () -> Void
}

final class RecoveryWindowController: NSWindowController {
    private let model: RecoveryModel

    init(actions: RecoveryActions) {
        model = RecoveryModel(actions: actions)
        let hosting = NSHostingController(rootView: RecoveryView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Ledge Recovery"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 620))
        window.minSize = NSSize(width: 480, height: 400)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        model.refresh()
        model.startTimer()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

extension RecoveryWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // No reads while nobody is looking.
        model.stopTimer()
    }
}

final class RecoveryModel: ObservableObject {
    @Published var report: RecoveryReport?
    @Published var lastActionOutcome: String?
    private let actions: RecoveryActions
    private var timer: Timer?

    init(actions: RecoveryActions) {
        self.actions = actions
    }

    func refresh() {
        report = actions.gather()
    }

    /// 20 seconds: the same throttle the menu bar health check uses, far
    /// below the 5-minute grace, and only while the window is on screen.
    func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func retryFiling() {
        lastActionOutcome = actions.retryFiling()
        refresh()
    }

    func revealFolder() { actions.revealFolder() }
    func revealSafetyCopies() { actions.revealSafetyCopies() }

    func copyReport() {
        guard let report else { return }
        let text = report.diagnosticText()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastActionOutcome = "Report copied. It holds counts, stamps and digests, never your text."
    }
}

struct RecoveryView: View {
    @ObservedObject var model: RecoveryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let report = model.report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        section("Folder") {
                            row("Path", report.folderDisplayPath)
                            row("Reachable", report.folderReachable ? "yes" : "no")
                            if report.inboxExists {
                                row("inbox.md", "\(report.inboxBytes ?? 0) bytes, modified \(age(report.inboxModified, report))")
                            } else {
                                row("inbox.md", "missing")
                            }
                            row("Download state", RecoveryReport.describe(report.inboxDownload))
                            if let entries = report.inboxEntries, let days = report.inboxDays {
                                row("Parsed", "\(entries) entries across \(days) days")
                            } else {
                                row("Parsed", "not readable locally")
                            }
                            row("Digest", report.inboxDigest ?? "unreadable")
                            if !report.lastLoadRepairs.isEmpty {
                                row("Repairs pending", "\(report.lastLoadRepairs.count)")
                            }
                        }

                        section("Sync") {
                            row("Health", report.syncHealthLine ?? "healthy, nothing to report")
                            if report.heartbeats.isEmpty {
                                row("Heartbeats", "none")
                            }
                            ForEach(Array(report.heartbeats.enumerated()), id: \.offset) { _, beat in
                                let agree: String = {
                                    guard let d = beat.digest, let mine = report.inboxDigest else { return "no digest" }
                                    return d == mine ? "same bytes" : "different bytes"
                                }()
                                row(beat.isSelf ? "\(beat.device) (this Mac)" : beat.device,
                                    "\(age(beat.at, report)), \(beat.platform) \(beat.version), \(agree)")
                            }
                            row("Unresolved conflicts", "\(report.conflictVersions)")
                            row("Last install here", age(report.lastInstall, report))
                        }

                        section("Captures") {
                            row("Waiting in spool", report.spool.count == 0
                                ? "none"
                                : "\(report.spool.count)" + (report.spool.oldest.map { ", oldest \(age($0, report))" } ?? ""))
                            row("Capture log here", "\(report.captureLogEntries) recorded")
                            row("Unaccounted", report.unaccounted.isEmpty ? "none" : "\(report.unaccounted.count)")
                            ForEach(Array(report.unaccounted.prefix(20).enumerated()), id: \.offset) { _, item in
                                row("", "\(LedgeFormat.spoolFormatter.string(from: item.at)) from \(item.device)")
                            }
                            if let bytes = report.editorJournalBytes {
                                row("Editor journal", "present, \(bytes) bytes not yet saved to the inbox")
                            } else {
                                row("Editor journal", "none")
                            }
                        }

                        section("Incidents, last 30 days") {
                            let s = report.incidentSummary30d
                            row("Count", "\(s.count)")
                            if s.count > 0 {
                                row("Total", LedgeFormat.roughDuration(s.totalDuration))
                                row("Longest", LedgeFormat.roughDuration(s.longest))
                                row("Within an hour of an install", "\(s.withinAnHourOfInstall)")
                                row("Ongoing", "\(s.ongoing)")
                            }
                            ForEach(Array(report.incidents.suffix(10).reversed().enumerated()), id: \.offset) { _, incident in
                                let end = incident.endedAt.map { LedgeFormat.spoolFormatter.string(from: $0) } ?? "ongoing"
                                row("", "\(incident.kind.rawValue), \(incident.observer) vs \(incident.peer ?? "?"): \(LedgeFormat.spoolFormatter.string(from: incident.startedAt)) to \(end)")
                            }
                        }

                        section("Local safety copies") {
                            if let b = report.backups, b.count > 0 {
                                row("Backups", "\(b.count), newest \(age(b.newest, report)), \(b.bytes) bytes")
                            } else {
                                row("Backups", "none yet")
                            }
                        }

                        Text("Generated \(LedgeFormat.spoolFormatter.string(from: report.generatedAt)). Refreshes every 20 seconds while open. Nothing here reads your notes' text.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                }
            } else {
                Text("Reading...").padding()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Refresh") { model.refresh() }
                    Button("Retry filing") { model.retryFiling() }
                        .help("Fold anything waiting in the spool and any conflict versions into the inbox, through the ordinary save path.")
                    Button("Reveal folder") { model.revealFolder() }
                    Button("Reveal safety copies") { model.revealSafetyCopies() }
                        .help("Opens the local folder holding the capture log, the editor journal and backups. It is outside iCloud on purpose.")
                    Spacer()
                    Button("Copy diagnostic report") { model.copyReport() }
                }
                if let outcome = model.lastActionOutcome {
                    Text(outcome).font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    private func age(_ d: Date?, _ report: RecoveryReport) -> String {
        guard let d else { return "never" }
        return LedgeFormat.roughAge(report.generatedAt.timeIntervalSince(d))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .frame(width: 170, alignment: .trailing)
                .foregroundColor(.secondary)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
    }
}

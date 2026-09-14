// App lifecycle: bootstrap the store, register the hotkey, put up the menu bar item.
// Built by Claude (Anthropic).

import AppKit
#if canImport(LedgeCore)
import LedgeCore
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var store: LedgeStore!
    private(set) var settings: LedgeSettings!
    private var panelController: PanelController!
    private var statusItemController: StatusItemController!
    private let hotkey = HotkeyManager()
    private var folderWatches: [DispatchSourceFileSystemObject] = []
    private var refreshWork: DispatchWorkItem?
    private var drainTimer: Timer?
    private var dragCapture: DragJiggleCaptureController?
    private var settingsWindow: SettingsWindowController?
    private var recoveryWindow: RecoveryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = LedgeStore.defaultRoot()
        store = LedgeStore(root: root)
        do {
            try store.bootstrap()
        } catch {
            NSLog("Ledge: bootstrap failed: \(error.localizedDescription)")
        }
        settings = LedgeSettings.load(from: store.settingsURL)

        panelController = PanelController(store: store, settings: settings)
        panelController.heartbeatWriter = { [weak self] force in self?.writeHeartbeat(force: force) }
        panelController.syncHealthProvider = { [weak self] in
            self?.updateSyncHealth()
            return self?.currentSyncHealth
        }
        statusItemController = StatusItemController(
            togglePanel: { [weak self] in self?.panelController.toggle() },
            openFolder: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.activateFileViewerSelecting([self.store.inboxURL])
            },
            capture: { [weak self] text in self?.quickCapture(text) ?? false },
            openSettings: { [weak self] in self?.showSettings() },
            openRecovery: { [weak self] in self?.showRecovery() }
        )

        dragCapture = DragJiggleCaptureController(
            onDrop: { [weak self] text in self?.quickCapture(text) ?? false }
        )

        hotkey.onHotkey = { [weak self] in self?.panelController.toggle() }
        hotkey.register(settings.hotkey)

        // Quiet maintenance on launch: fold phone captures in, let old days rest in the Attic.
        maintain()
        writeHeartbeat(force: true)

        startFolderWatch()
        startDrainTimer()
    }

    // MARK: Sync health (brief 2026-09-03, item M4)

    static let appVersion: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"

    private var lastHeartbeatWrite: Date = .distantPast
    private var lastHeartbeatDigest: String?

    /// This Mac's "I was here" stamp in .ledge/. Written at launch, whenever
    /// the inbox bytes change, and otherwise at most hourly.
    ///
    /// The first version rewrote it every 5 minutes forever. This app is
    /// resident all day, so that turned an idle folder into a permanent iCloud
    /// writer and roughly doubled the folder's upload traffic (bird: about 14
    /// uploads an hour before 0.4.2, 24 after, 38 once the phone joined in).
    /// Health monitoring must not itself be a load on the transport it
    /// watches. `force` is for launch and for a capture that just landed.
    func writeHeartbeat(force: Bool = false) {
        let now = Date()
        let digest = store.inboxDigest()
        // ADAPTIVE CADENCE. Hourly while nobody is watching, but every 10
        // minutes while a peer is actually active, because the disagreement
        // check only trusts a peer seen within 15 minutes. With a flat hourly
        // stamp this Mac was outside that window for 45 minutes of every hour,
        // so the warning built for the 2026-09-03 stall could not fire and
        // "Up to date with MacBook M4" was unreachable on the phone. The two
        // halves disagreed about their own contract (review 2026-09-03).
        //
        // Cost when the phone is idle: 1 write an hour. When it is in use:
        // 6 an hour, against 12 in the version that caused the churn
        // regression, and only while someone is there to read the answer.
        let peerActive = store.readHeartbeats().contains { beat in
            beat.device != PanelContentViewController.deviceLabel
                && now.timeIntervalSince(beat.at) <= 30 * 60
        }
        let interval: TimeInterval = peerActive ? 600 : 3600
        let due = now.timeIntervalSince(lastHeartbeatWrite) >= interval
        guard force || due || digest != lastHeartbeatDigest else { return }
        do {
            try store.writeHeartbeat(
                device: PanelContentViewController.deviceLabel,
                version: Self.appVersion,
                platform: "macOS",
                now: now
            )
            lastHeartbeatWrite = now
            lastHeartbeatDigest = digest
        } catch {
            NSLog("Ledge: heartbeat not written: \(error.localizedDescription)")
        }
    }

    /// The sync-health line for the menu bar: is the other device stranded on
    /// different bytes, or has it gone quiet? Nil when healthy.
    private static let disagreementSinceKey = "ledge.disagreementSince"
    private static let disagreementIdentityKey = "ledge.disagreementKey"
    private var lastHealthCheck: Date = .distantPast

    /// Throttled: the open panel asks on its 2-second timer, and each call
    /// reads the heartbeat directory and hashes inbox.md. Once every 20
    /// seconds is far below the 5-minute grace and costs nothing.
    func updateSyncHealth(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastHealthCheck) >= 20 else { return }
        lastHealthCheck = now
        let defaults = UserDefaults.standard
        let health = LedgeStore.evaluatePeer(
            beats: store.readHeartbeats(),
            selfDevice: PanelContentViewController.deviceLabel,
            selfDigest: store.inboxDigest(),
            disagreementSince: defaults.object(forKey: Self.disagreementSinceKey) as? Date,
            disagreementKey: defaults.string(forKey: Self.disagreementIdentityKey),
            now: now
        )
        if let since = health.disagreementSince, let key = health.disagreementKey {
            defaults.set(since, forKey: Self.disagreementSinceKey)
            defaults.set(key, forKey: Self.disagreementIdentityKey)
        } else {
            defaults.removeObject(forKey: Self.disagreementSinceKey)
            defaults.removeObject(forKey: Self.disagreementIdentityKey)
        }
        // Count every stall, so the question "how often does this happen"
        // has a countable answer instead of a remembered one.
        let me = PanelContentViewController.deviceLabel
        let peerName = store.readHeartbeats().first { $0.device != me }?.device
        if health.line != nil, let since = health.disagreementSince {
            store.noteIncident(SyncIncident(
                kind: .disagreement,
                observer: me,
                startedAt: since,
                endedAt: nil,
                peer: peerName,
                version: Self.appVersion,
                secondsAfterInstall: store.secondsSinceLastInstall(now: since)
            ))
        } else if health.disagreementSince == nil {
            store.closeIncident(kind: .disagreement, observer: me, peer: peerName)
        }

        // A safety net nobody can see is not a safety net. If the write-ahead
        // log holds a capture that was never confirmed and is not in the
        // inbox, say so on the one always-visible surface.
        if let inbox = try? store.loadInbox() {
            let missing = Self.captureLog.unrecovered(comparedTo: inbox)
            statusItemController?.setCaptureAlert(
                missing.isEmpty ? nil
                    : (missing.count == 1
                        ? "1 capture is not accounted for"
                        : "\(missing.count) captures are not accounted for")
            )
        }

        currentSyncHealth = health.line
        statusItemController?.setSyncHealth(health.line)
        if let line = health.line, line != lastSyncHealth {
            NSLog("Ledge: sync health: \(line)")
        }
        lastSyncHealth = health.line
    }

    private var lastSyncHealth: String?

    /// The most recent evaluation, for surfaces that ask rather than observe.
    private(set) var currentSyncHealth: String?

    /// Capture trust: fold out-of-app captures in even when the panel is never
    /// summoned (a capture once sat in the spool for eleven days while the app
    /// ran). Slow on purpose; the open panel's own 2-second heartbeat covers
    /// the visible case, so this only runs while the panel is tucked away.
    /// Sync health is checked on every tick regardless, because the panel
    /// being tucked away is exactly when a stall goes unnoticed.
    private func startDrainTimer() {
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Both of these run whether or not the panel is open: the panel
            // being tucked away is exactly when a stall goes unnoticed, and
            // the peer needs a live stamp from us to disagree with.
            self.writeHeartbeat()
            self.updateSyncHealth(force: true)
            guard !self.panelController.isVisible else { return }
            self.maintain()
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        drainTimer = timer
    }

    /// Watch the Ledge folder for writes landed by iCloud (the iPhone's
    /// inbox.md, a spool append) and let the open panel pick them up.
    ///
    /// History: this used to be an NSMetadataQuery scoped to
    /// NSMetadataQueryUbiquitousDocumentsScope. That scope covers the calling
    /// app's own ubiquity container, and this app deliberately has none and is
    /// signed with no entitlements at all, so the query gathered zero items
    /// and the comment above it described behaviour that never happened
    /// (brief 2026-09-03, failure mode L). A vnode source on the folder needs
    /// no entitlement: iCloud replaces files in place, which is a directory
    /// write event.
    /// A vnode source watches ONE directory, not a tree. inbox.md lives in the
    /// root, but the spool lives in capture/, so an out-of-app capture landing
    /// in capture/drop.md fires nothing on the root watch. Both are watched
    /// explicitly (independent review, 2026-09-03).
    private func startFolderWatch() {
        for url in [store.root, store.captureURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else {
                NSLog("Ledge: folder watch could not open \(url.lastPathComponent)")
                continue
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .attrib],
                queue: .main
            )
            source.setEventHandler { [weak self] in self?.folderChanged() }
            source.setCancelHandler { close(fd) }
            source.resume()
            folderWatches.append(source)
        }
    }

    private var folderEvents = 0

    private func folderChanged() {
        folderEvents += 1
        // Ask for the newest bytes of the two files that matter; no-ops when
        // they are already current.
        try? FileManager.default.startDownloadingUbiquitousItem(at: store.inboxURL)
        try? FileManager.default.startDownloadingUbiquitousItem(at: store.spoolURL)
        // Coalesce the burst iCloud produces per change, then let the open
        // panel pick it up. Logged so `log stream --process Ledge` can prove
        // the watcher is alive, which its predecessor never could.
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSLog("Ledge: folder changed (event \(self.folderEvents)), refreshing panel if idle")
            self.panelController.refreshFromCloudIfIdle()
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    /// The Settings window. Changes save immediately, re-register the hotkey,
    /// and resize the open panel live.
    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings) { [weak self] newSettings in
                guard let self else { return }
                self.settings = newSettings
                try? newSettings.save(to: self.store.settingsURL)
                self.hotkey.register(newSettings.hotkey)
                self.panelController.apply(newSettings)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.center()
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Recovery (observational first, 2026-09-14)

    /// The local folder outside iCloud that holds this Mac's safety copies:
    /// the capture log, the editor recovery journal, and backups.
    static var safetyCopiesURL: URL {
        CaptureLog.defaultURL().deletingLastPathComponent()
    }

    /// Everything the Recovery window shows, read from disk right now. Reads
    /// only; the report's own tests prove it writes nothing into the folder
    /// and carries no capture text.
    func gatherRecoveryReport() -> RecoveryReport {
        updateSyncHealth()
        return RecoveryReport.gather(RecoveryReport.Sources(
            store: store,
            captureLog: Self.captureLog,
            editorJournalURL: PanelContentViewController.recoveryJournalURL,
            backups: nil,
            selfDevice: PanelContentViewController.deviceLabel,
            appVersion: Self.appVersion,
            platform: "macOS",
            syncHealthLine: currentSyncHealth
        ))
    }

    /// The one write Recovery may ask for: the ordinary drain-and-commit path,
    /// run now instead of on the next timer tick. Nothing here is new code
    /// with a new failure mode; it is the same path the 5-minute maintenance
    /// takes, with its outcome put into words.
    func retryFiling() -> String {
        do {
            // loadInbox already folds conflict versions and repairs headers,
            // saving when it changed anything; the spool drain is the step
            // that can still be waiting. Same order as maintain().
            var inbox = try store.loadInbox()
            let repairs = store.lastLoadRepairs
            let batch = try store.drainSpool(into: &inbox)
            if batch.added > 0 {
                try store.saveInbox(inbox)
            }
            try batch.commit()
            writeHeartbeat(force: batch.added > 0)
            updateSyncHealth(force: true)
            panelController.maintenanceFailure = nil
            var parts: [String] = []
            switch batch.added {
            case 0: break
            case 1: parts.append("1 capture folded into the inbox")
            default: parts.append("\(batch.added) captures folded into the inbox")
            }
            if !repairs.isEmpty {
                parts.append(repairs.count == 1 ? "1 repair applied" : "\(repairs.count) repairs applied")
            }
            if parts.isEmpty {
                return "Nothing was waiting. The spool is empty and the inbox needed no repair."
            }
            return parts.joined(separator: "; ") + "."
        } catch {
            return "Could not file right now: \(error.localizedDescription). Nothing was lost; the spool keeps what it had."
        }
    }

    private func showRecovery() {
        if recoveryWindow == nil {
            recoveryWindow = RecoveryWindowController(actions: RecoveryActions(
                gather: { [weak self] in
                    self?.gatherRecoveryReport() ?? RecoveryReport.gather(RecoveryReport.Sources(
                        store: LedgeStore(root: LedgeStore.defaultRoot()),
                        selfDevice: "Mac", appVersion: Self.appVersion, platform: "macOS"))
                },
                retryFiling: { [weak self] in self?.retryFiling() ?? "Ledge is not ready." },
                revealFolder: { [weak self] in
                    guard let self else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([self.store.inboxURL])
                },
                revealSafetyCopies: {
                    let url = Self.safetyCopiesURL
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            ))
        }
        recoveryWindow?.show()
    }

    /// Shared quiet capture path for the mini-popover (A1) and the edge drop
    /// strip (A3). Full store guards apply; failure returns false, loses nothing.
    /// This Mac's device-local write-ahead log, outside the iCloud folder.
    static let captureLog = CaptureLog(url: CaptureLog.defaultURL())

    private func quickCapture(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Write-ahead before anything that can fail.
        let logged = try? Self.captureLog.record(
            text: trimmed,
            device: PanelContentViewController.deviceLabel,
            intent: "inbox"
        )
        do {
            var inbox = try store.loadInbox()
            let batch = try store.drainSpool(into: &inbox)
            inbox.prepend(text: trimmed, at: Date(), device: PanelContentViewController.deviceLabel)
            try store.saveInbox(inbox)
            try batch.commit()
            if let logged { Self.captureLog.confirm(logged.id) }
            writeHeartbeat(force: true)
            return true
        } catch {
            return false
        }
    }

    private func maintain() {
        do {
            var inbox = try store.loadInbox()
            if !store.lastLoadRepairs.isEmpty {
                NSLog("Ledge: repaired inbox.md: \(store.lastLoadRepairs.joined(separator: "; "))")
            }
            var dirty = false
            let batch = try store.drainSpool(into: &inbox)
            if batch.added > 0 { dirty = true }
            if try store.age(&inbox, olderThanDays: settings.agingDays) > 0 { dirty = true }
            if dirty { try store.saveInbox(inbox) }
            try batch.commit()
            writeHeartbeat()
            panelController.maintenanceFailure = nil
            updateSyncHealth()
        } catch {
            // Logged, and remembered: the next summon shows it in the header
            // instead of a fresh "Inbox" that pretends nothing happened.
            NSLog("Ledge: maintenance skipped: \(error.localizedDescription)")
            panelController.maintenanceFailure = error.localizedDescription
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController.saveIfNeeded()
        hotkey.unregister()
    }
}

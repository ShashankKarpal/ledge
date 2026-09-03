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
    private var folderWatch: DispatchSourceFileSystemObject?
    private var folderWatchFD: Int32 = -1
    private var refreshWork: DispatchWorkItem?
    private var drainTimer: Timer?
    private var dragCapture: DragJiggleCaptureController?
    private var settingsWindow: SettingsWindowController?

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
        statusItemController = StatusItemController(
            togglePanel: { [weak self] in self?.panelController.toggle() },
            openFolder: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.activateFileViewerSelecting([self.store.inboxURL])
            },
            capture: { [weak self] text in self?.quickCapture(text) ?? false },
            openSettings: { [weak self] in self?.showSettings() }
        )

        dragCapture = DragJiggleCaptureController(
            onDrop: { [weak self] text in self?.quickCapture(text) ?? false }
        )

        hotkey.onHotkey = { [weak self] in self?.panelController.toggle() }
        hotkey.register(settings.hotkey)

        // Quiet maintenance on launch: fold phone captures in, let old days rest in the Attic.
        maintain()
        writeHeartbeat()

        startFolderWatch()
        startDrainTimer()
    }

    // MARK: Sync health (brief 2026-09-03, item M4)

    static let appVersion: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"

    /// This Mac's "I was here" stamp in .ledge/. Written at launch, after every
    /// maintenance pass, and by the panel on every successful commit. The
    /// phone reads it to tell whether the Mac has been heard from.
    func writeHeartbeat() {
        do {
            try store.writeHeartbeat(
                device: PanelContentViewController.deviceLabel,
                version: Self.appVersion,
                platform: "macOS"
            )
        } catch {
            NSLog("Ledge: heartbeat not written: \(error.localizedDescription)")
        }
    }

    /// Capture trust: fold out-of-app captures in even when the panel is never
    /// summoned (a capture once sat in the spool for eleven days while the app
    /// ran). Slow on purpose; the open panel's own 2-second heartbeat covers
    /// the visible case, so this only runs while the panel is tucked away.
    private func startDrainTimer() {
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            guard let self, !self.panelController.isVisible else { return }
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
    private func startFolderWatch() {
        let path = store.root.path
        folderWatchFD = open(path, O_EVTONLY)
        guard folderWatchFD >= 0 else {
            NSLog("Ledge: folder watch could not open \(path)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: folderWatchFD,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.folderChanged() }
        source.setCancelHandler { [fd = folderWatchFD] in close(fd) }
        source.resume()
        folderWatch = source
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

    /// Shared quiet capture path for the mini-popover (A1) and the edge drop
    /// strip (A3). Full store guards apply; failure returns false, loses nothing.
    private func quickCapture(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            var inbox = try store.loadInbox()
            _ = try? store.drainSpool(into: &inbox)
            inbox.prepend(text: trimmed, at: Date(), device: PanelContentViewController.deviceLabel)
            try store.saveInbox(inbox)
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
            if try store.drainSpool(into: &inbox) > 0 { dirty = true }
            if try store.age(&inbox, olderThanDays: settings.agingDays) > 0 { dirty = true }
            if dirty { try store.saveInbox(inbox) }
            writeHeartbeat()
            panelController.maintenanceFailure = nil
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

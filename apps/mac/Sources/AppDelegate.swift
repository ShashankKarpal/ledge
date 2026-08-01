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
    private var syncWatcher: NSMetadataQuery?
    private var refreshWork: DispatchWorkItem?
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

        startSyncWatcher()
    }

    /// Keep the Mac's local copies of the Ledge files fresh. Without a live
    /// metadata query nothing tells macOS that anyone cares about this folder,
    /// so changes written by the iPhone can sit undownloaded indefinitely.
    /// The query watches the folder and force-downloads anything not current.
    private func startSyncWatcher() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K CONTAINS[c] '/Ledge/'", NSMetadataItemPathKey)
        query.notificationBatchingInterval = 2
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncWatcherFired(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncWatcherFired(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        query.start()
        syncWatcher = query
    }

    @objc private func syncWatcherFired(_ note: Notification) {
        guard let query = syncWatcher else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        for case let item as NSMetadataItem in query.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: path))
            }
        }
        // Give the download a beat to land, then let the open panel pick it up.
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.panelController.refreshFromCloudIfIdle()
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
            var dirty = false
            if try store.drainSpool(into: &inbox) > 0 { dirty = true }
            if try store.age(&inbox, olderThanDays: settings.agingDays) > 0 { dirty = true }
            if dirty { try store.saveInbox(inbox) }
        } catch {
            NSLog("Ledge: maintenance skipped: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController.saveIfNeeded()
        hotkey.unregister()
    }
}

// The menu bar residue: Ledge's only always-visible presence. Point of performance,
// not a badge farm. The icon never changes, never counts, never turns red.
// Click: mini-capture popover (A1). Right-click: the menu.
// Built by Claude (Anthropic).

import AppKit

final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem!
    private let togglePanel: () -> Void
    private let openFolder: () -> Void
    private let capture: (String) -> Bool
    private let openSettings: () -> Void
    private let openRecovery: () -> Void
    private var popover: NSPopover?
    private let menu = NSMenu()
    private let syncHealthItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let captureAlertItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    /// Show or hide the sync-health row. Pass nil when healthy.
    func setSyncHealth(_ line: String?) {
        if let line {
            syncHealthItem.title = line
            syncHealthItem.isHidden = false
        } else {
            syncHealthItem.isHidden = true
        }
    }

    /// Show or hide the unaccounted-captures row. Pass nil when everything the
    /// write-ahead log recorded has been found. This is the only place the
    /// safety net becomes visible, so it must not be silent when it matters.
    func setCaptureAlert(_ line: String?) {
        if let line {
            captureAlertItem.title = line
            captureAlertItem.isHidden = false
        } else {
            captureAlertItem.isHidden = true
        }
    }

    init(togglePanel: @escaping () -> Void, openFolder: @escaping () -> Void, capture: @escaping (String) -> Bool, openSettings: @escaping () -> Void, openRecovery: @escaping () -> Void) {
        self.togglePanel = togglePanel
        self.openFolder = openFolder
        self.capture = capture
        self.openSettings = openSettings
        self.openRecovery = openRecovery
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // The Step mark, monochrome template. macOS inverts it for the
        // menu bar appearance; the SF Symbol stays as a build-order fallback.
        let icon = NSImage(named: "MenuBarIconTemplate")
            ?? NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Ledge")
        icon?.isTemplate = true
        icon?.accessibilityDescription = "Ledge"
        statusItem.button?.image = icon
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let open = NSMenuItem(title: "Open Ledge Panel", action: #selector(openAction), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let mini = NSMenuItem(title: "Quick Capture", action: #selector(miniAction), keyEquivalent: "")
        mini.target = self
        menu.addItem(mini)

        let folder = NSMenuItem(title: "Open Notes Folder in Finder", action: #selector(folderAction), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        let prefs = NSMenuItem(title: "Settings\u{2026}", action: #selector(settingsAction), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        // Recovery: where to look when sync feels wrong. Observational first;
        // safe actions only. Always present so it can be found before it is
        // needed, never highlighted, per the no-badges rule.
        let recovery = NSMenuItem(title: "Recovery\u{2026}", action: #selector(recoveryAction), keyEquivalent: "")
        recovery.target = self
        menu.addItem(recovery)

        menu.addItem(.separator())

        // Sync health, the one line that is allowed to say something is wrong.
        // Hidden while healthy, per the no-badges rule. It exists because on
        // 2026-09-03 the iPhone's iCloud daemon stalled for two hours and no
        // surface anywhere said so; the panel was tucked away the whole time.
        syncHealthItem.isEnabled = false
        syncHealthItem.isHidden = true
        menu.addItem(syncHealthItem)

        // Clickable: the row that says captures are unaccounted for opens the
        // screen that lists when they were made and what to do about it.
        captureAlertItem.target = self
        captureAlertItem.action = #selector(recoveryAction)
        captureAlertItem.isHidden = true
        menu.addItem(captureAlertItem)

        let hint = NSMenuItem(title: "Summon: Option+Space · Esc tucks away", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        let hint2 = NSMenuItem(title: "Click icon: quick capture · Right-click: this menu", action: nil, keyEquivalent: "")
        hint2.isEnabled = false
        menu.addItem(hint2)

        let credit = NSMenuItem(title: "Ledge, built by Claude (Anthropic) · MIT", action: nil, keyEquivalent: "")
        credit.isEnabled = false
        menu.addItem(credit)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Ledge", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func togglePopover() {
        if let existing = popover, existing.isShown {
            existing.performClose(nil)
            popover = nil
            return
        }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = NSSize(width: 300, height: 96)
        pop.contentViewController = MiniCaptureViewController(
            capture: capture,
            onDone: { [weak self] in
                self?.popover?.performClose(nil)
                self?.popover = nil
            }
        )
        if let button = statusItem.button {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            pop.contentViewController?.view.window?.makeKey()
        }
        popover = pop
    }

    @objc private func openAction() { togglePanel() }
    @objc private func miniAction() { togglePopover() }
    @objc private func folderAction() { openFolder() }
    @objc private func settingsAction() { openSettings() }
    @objc private func recoveryAction() { openRecovery() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}

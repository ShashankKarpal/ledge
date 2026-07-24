// The menu bar residue: Ledge's only always-visible presence. Point of performance,
// not a badge farm. The icon never changes, never counts, never turns red.
// Built by Claude (Anthropic).

import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let togglePanel: () -> Void
    private let openFolder: () -> Void

    init(togglePanel: @escaping () -> Void, openFolder: @escaping () -> Void) {
        self.togglePanel = togglePanel
        self.openFolder = openFolder
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "sidebar.right",
            accessibilityDescription: "Ledge"
        )

        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Ledge", action: #selector(openAction), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let folder = NSMenuItem(title: "Open Notes Folder in Finder", action: #selector(folderAction), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        menu.addItem(.separator())

        let hint = NSMenuItem(title: "Summon: Option+Space · Esc tucks away", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        let credit = NSMenuItem(title: "Ledge, built by Claude (Anthropic) · MIT", action: nil, keyEquivalent: "")
        credit.isEnabled = false
        menu.addItem(credit)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Ledge", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func openAction() { togglePanel() }
    @objc private func folderAction() { openFolder() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}

// The edge panel: a Spotlight-style non-activating NSPanel that slides in at the
// right edge of the screen the cursor is on. Zero permission prompts by design.
// Built by Claude (Anthropic).

import AppKit
#if canImport(LedgeCore)
import LedgeCore
#endif

final class LedgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelController {
    private let store: LedgeStore
    private var settings: LedgeSettings
    private var panel: LedgePanel?
    private var refreshTimer: Timer?
    private var content: PanelContentViewController?
    private var keyMonitor: Any?
    private var animating = false

    init(store: LedgeStore, settings: LedgeSettings) {
        self.store = store
        self.settings = settings
    }

    deinit {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Live settings update from the Settings window. Width applies to the
    /// open panel immediately and to every future summon.
    func apply(_ newSettings: LedgeSettings) {
        settings = newSettings
        if let panel, panel.isVisible, !animating {
            panel.setFrame(targetFrame(), display: true)
        }
    }

    /// Reload the open panel after iCloud pulled fresh bytes. Safe by design:
    /// the content view refuses unless the editor is clean.
    func refreshFromCloudIfIdle() {
        guard isVisible else { return }
        content?.refreshFromDiskIfClean()
    }

    /// While the panel is visible, re-check the folder every couple of
    /// seconds: each pass nudges iCloud for newer bytes and reloads the
    /// editor when it is clean. Stopped on dismiss; zero cost while tucked.
    private func startRefreshTimer() {
        stopRefreshTimer()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.content?.refreshFromDiskIfClean()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    func saveIfNeeded() {
        content?.commit()
    }

    // MARK: Show and dismiss

    func show() {
        guard !animating else { return }
        let panel = ensurePanel()
        content?.prepareForSummon()
        startRefreshTimer()

        let target = targetFrame()
        var start = target
        start.origin.x += 28
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        animating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.reduceMotion ? 0.1 : Theme.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            self?.animating = false
            self?.content?.focusEditor()
        })
    }

    func dismiss() {
        guard let panel, panel.isVisible, !animating else { return }
        stopRefreshTimer()
        content?.commit()
        content?.showTuckedConfirmation()

        var target = panel.frame
        target.origin.x += 28
        animating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.reduceMotion ? 0.1 : Theme.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.animating = false
            panel.orderOut(nil)
            self?.content?.resetHeader()
        })
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: Setup

    private func ensurePanel() -> LedgePanel {
        if let panel { return panel }

        let contentVC = PanelContentViewController(store: store, settings: settings)
        contentVC.requestDismiss = { [weak self] in self?.dismiss() }

        let panel = LedgePanel(
            contentRect: targetFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.contentViewController = contentVC

        installKeyMonitor(for: panel, content: contentVC)

        self.panel = panel
        self.content = contentVC
        return panel
    }

    /// The screen the cursor is on, right edge, full visible height.
    private func targetFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let margin: CGFloat = 10
        let width = CGFloat(settings.panelWidth)
        return NSRect(
            x: visible.maxX - width - margin,
            y: visible.minY + margin,
            width: width,
            height: visible.height - margin * 2
        )
    }

    /// One local monitor handles Esc and the command keys while the panel is key.
    private func installKeyMonitor(for panel: LedgePanel, content: PanelContentViewController) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel, weak content] event in
            guard let self, let panel, let content, event.window === panel else { return event }

            if event.keyCode == 53 { // Escape
                if content.handleEscape() { self.dismiss() }
                return nil
            }
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "k": content.showSearch(); return nil
                case "l": content.showLoops(); return nil
                case "p": content.showNotes(); return nil
                case "n": content.newNote(); return nil
                default: break
                }
            }
            return event
        }
    }
}

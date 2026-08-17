// Panel content: header, the inbox editor, overlay hosting, autosave, capture flow.
// Chrome-zero: no toolbar; the command keys and the slash of habit carry everything.
// Built by Claude (Anthropic).

import AppKit
import SwiftUI
#if canImport(LedgeCore)
import LedgeCore
#endif

final class PanelContentViewController: NSViewController, NSTextViewDelegate {
    enum Mode {
        case inbox
        case note(URL)
    }

    let store: LedgeStore
    private let settings: LedgeSettings
    private(set) var mode: Mode = .inbox

    private let headerLabel = NSTextField(labelWithString: "Inbox")
    private let hintLabel = NSTextField(labelWithString: "Esc tucks away · ⌘K search · ⌘L loops · ⌘P notes")
    private var scrollView: NSScrollView!
    private var textView: EditorTextView!
    private var stack: NSStackView!
    private var overlayHost: NSHostingView<AnyView>?

    private var styleWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?

    var requestDismiss: (() -> Void)?

    init(store: LedgeStore, settings: LedgeSettings) {
        self.store = store
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: View construction

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = Theme.panelRadius
        container.layer?.borderWidth = 1

        headerLabel.font = Theme.dayFont
        headerLabel.textColor = Theme.textMuted

        hintLabel.font = Theme.metaFont
        hintLabel.textColor = Theme.textAged
        hintLabel.lineBreakMode = .byTruncatingTail

        textView = EditorTextView.make()
        textView.delegate = self
        textView.onCheckboxToggle = { [weak self] in self?.scheduleSave() }
        textView.assetsDirectory = { [weak self] in
            guard let self else { return nil }
            return self.store.inboxURL.deletingLastPathComponent()
                .appendingPathComponent("assets", isDirectory: true)
        }

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        stack = NSStackView(views: [headerLabel, scrollView, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.distribution = .fill
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 14, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // The editor takes all remaining height; labels hug their content.
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        headerLabel.setContentHuggingPriority(.required, for: .vertical)
        hintLabel.setContentHuggingPriority(.required, for: .vertical)

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            headerLabel.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            hintLabel.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        self.view = container
        applyThemeColors()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyThemeColors()
    }

    private func applyThemeColors() {
        guard let layer = view.layer else { return }
        let appearance = view.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = Theme.surface.cgColor
            layer.borderColor = Theme.border.cgColor
        }
    }

    /// True once the editor holds real content from a load. Commit refuses to
    /// run before that: an unpopulated editor must never be saved as truth.
    private var editorPopulated = false

    /// Exactly what was last loaded into or saved from the editor; commit
    /// skips no-op saves so a mere summon never rewrites the file or races
    /// an in-flight write from another device.
    private var lastSetEditorText = ""

    /// Raw disk bytes as of the last refresh check; skip UI work when nothing
    /// on disk actually changed (also avoids minute-drift caret jumps).
    private var lastSeenDiskRaw = ""

    /// Label written into every entry captured on this Mac. Override with:
    /// defaults write com.example.ledge.mac deviceLabel "MacBook M4"
    static let deviceLabel: String = {
        if let custom = UserDefaults.standard.string(forKey: "deviceLabel"), !custom.isEmpty {
            return custom
        }
        return Host.current().localizedName ?? "Mac"
    }()

    // MARK: Summon and commit

    /// Reload from disk, fold in phone captures, open a fresh timestamped entry.
    func prepareForSummon() {
        commit()
        closeOverlay()
        mode = .inbox
        resetHeader()

        do {
            try store.bootstrap()
            var inbox = try store.loadInbox()
            let drained = (try? store.drainSpool(into: &inbox)) ?? 0
            if drained > 0 {
                try store.saveInbox(inbox)
            }
            let newestIsEmpty = inbox.days.first?.entries.first?.text.isEmpty ?? false
            if !newestIsEmpty {
                inbox.prepend(text: "", at: Date(), device: Self.deviceLabel)
            }
            setEditorText(inbox.serialized())
            placeCaretAtFirstEntry()
            if drained > 0 {
                headerLabel.stringValue = "Inbox · \(drained) folded in from your devices"
            }
            maybeShowMorningLedge()
        } catch {
            headerLabel.stringValue = "Inbox · could not read the notes folder"
            headerLabel.textColor = Theme.attention
        }
    }

    // MARK: Morning Ledge

    private static let morningShownKey = "ledge.morningShownDay"

    /// On the first summon of a new day, surface where you left off. Once per
    /// day, only when something is actually open, dismissed by Esc or one click.
    private func maybeShowMorningLedge() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        guard UserDefaults.standard.string(forKey: Self.morningShownKey) != today else { return }
        UserDefaults.standard.set(today, forKey: Self.morningShownKey)
        let loops = store.openLoops(inbox: Inbox.parse(textView.string))
        guard !loops.isEmpty else { return }
        presentOverlay(AnyView(MorningOverlay(
            store: store,
            currentInbox: { [weak self] in Inbox.parse(self?.textView.string ?? "") },
            onComplete: { [weak self] loop in self?.completeLoop(loop) },
            onJump: { [weak self] loop in
                if loop.fileURL == self?.store.inboxURL {
                    self?.revealInInbox(snippet: "- [ ] " + loop.text)
                } else {
                    self?.openNote(loop.fileURL)
                }
            },
            onStart: { [weak self] in
                self?.closeOverlay()
                self?.focusEditor()
            }
        )), title: "Morning Ledge")
    }

    /// Persist the current surface. Empty entries evaporate; nothing else is touched.
    func commit() {
        saveWork?.cancel()
        guard editorPopulated, textView != nil else { return }
        if textView.string == lastSetEditorText { return }
        switch mode {
        case .inbox:
            var inbox = Inbox.parse(textView.string)
            inbox.removeEmptyEntries()
            try? store.saveInbox(inbox)
            lastSetEditorText = textView.string
        case .note(let url):
            try? store.saveNote(textView.string, to: url)
            lastSetEditorText = textView.string
        }
    }

    func focusEditor() {
        view.window?.makeFirstResponder(textView)
    }

    /// The capture-confirmation flick: a quiet check in the done color while the panel tucks.
    func showTuckedConfirmation() {
        headerLabel.stringValue = "✓ captured"
        headerLabel.textColor = Theme.done
    }

    /// Quietly reload from disk while the panel is open and idle. Called when
    /// the sync watcher pulls new bytes. Never touches unsaved typing: if the
    /// editor differs from what was loaded, this is a no-op and the merge
    /// guards reconcile everything on the next commit instead.
    func refreshFromDiskIfClean() {
        guard case .inbox = mode, textView != nil, textView.string == lastSetEditorText else { return }
        let raw = ((try? store.readString(store.inboxURL)) ?? nil) ?? ""
        // A new out-of-app capture changes the spool without touching inbox.md,
        // so the spool must be part of the "anything new?" check (iOS heartbeat parity).
        let spoolRaw = ((try? store.readString(store.spoolURL)) ?? nil) ?? ""
        if raw == lastSeenDiskRaw && LedgeFormat.trimEdges(spoolRaw).isEmpty { return }
        lastSeenDiskRaw = raw
        do {
            var inbox = try store.loadInbox()
            let drained = (try? store.drainSpool(into: &inbox)) ?? 0
            if drained > 0 {
                try? store.saveInbox(inbox)
            }
            let newestIsEmpty = inbox.days.first?.entries.first?.text.isEmpty ?? false
            if !newestIsEmpty {
                inbox.prepend(text: "", at: Date(), device: Self.deviceLabel)
            }
            let serialized = inbox.serialized()
            guard serialized != lastSetEditorText else { return }
            setEditorText(serialized)
            placeCaretAtFirstEntry()
            headerLabel.stringValue = "Inbox · updated from your devices"
        } catch {
            // Quiet by design; the next summon retries with full handling.
        }
    }

    func resetHeader() {
        switch mode {
        case .inbox: headerLabel.stringValue = "Inbox"
        case .note(let url): headerLabel.stringValue = LedgeStore.title(of: textView.string, fallback: url.lastPathComponent)
        }
        headerLabel.textColor = Theme.textMuted
    }

    /// Returns true when Escape should dismiss the whole panel.
    func handleEscape() -> Bool {
        if overlayHost != nil {
            closeOverlay()
            focusEditor()
            return false
        }
        if case .note = mode {
            switchToInbox()
            return false
        }
        return true
    }

    // MARK: Editor plumbing

    private func setEditorText(_ text: String) {
        editorPopulated = true
        lastSetEditorText = text
        textView.string = text
        MarkdownStyler.style(textView)
    }

    private func placeCaretAtFirstEntry() {
        let ns = textView.string as NSString
        let regex = try? NSRegularExpression(pattern: "^### \\d{2}:\\d{2}( · [^\\n]*)?[ \\t]*$", options: .anchorsMatchLines)
        let full = NSRange(location: 0, length: ns.length)
        if let match = regex?.firstMatch(in: textView.string, options: [], range: full) {
            let caret = min(match.range.location + match.range.length + 1, ns.length)
            textView.setSelectedRange(NSRange(location: caret, length: 0))
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        } else {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }

    func textDidChange(_ notification: Notification) {
        scheduleStyle()
        scheduleSave()
    }

    private func scheduleStyle() {
        styleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            MarkdownStyler.style(self.textView)
        }
        styleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commit() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: Notes

    func openNote(_ url: URL) {
        commit()
        closeOverlay()
        mode = .note(url)
        let content = ((try? store.readString(url)) ?? nil) ?? ""
        setEditorText(content)
        headerLabel.stringValue = LedgeStore.title(of: content, fallback: url.lastPathComponent)
        headerLabel.textColor = Theme.textMuted
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        focusEditor()
    }

    func switchToInbox() {
        commit()
        mode = .inbox
        prepareForSummon()
        focusEditor()
    }

    func newNote() {
        let alert = NSAlert()
        alert.messageText = "New note"
        alert.informativeText = "A named note for something that outgrew the inbox."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Title"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let title = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return }
            if let url = try? store.createNote(title: title) {
                openNote(url)
            }
        }
    }

    /// Scroll the inbox to the first occurrence of a snippet (search jump-back).
    func revealInInbox(snippet: String) {
        if case .note = mode { switchToInbox() }
        closeOverlay()
        let ns = textView.string as NSString
        let probe = String(snippet.prefix(40))
        let range = ns.range(of: probe)
        if range.location != NSNotFound {
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
        focusEditor()
    }

    /// Mark an open loop done at its source. Gentle: one checkbox, one write.
    func completeLoop(_ loop: OpenLoop) {
        let needle = "- [ ] " + loop.text
        let replacement = "- [x] " + loop.text
        if loop.fileURL == store.inboxURL {
            if case .inbox = mode {
                textView.string = textView.string.replacingOccurrences(of: needle, with: replacement)
                MarkdownStyler.style(textView)
                commit()
            }
        } else if let content = ((try? store.readString(loop.fileURL)) ?? nil) {
            let updated = content.replacingOccurrences(of: needle, with: replacement)
            try? store.saveNote(updated, to: loop.fileURL)
        }
    }

    // MARK: Overlays (SwiftUI inside the AppKit panel)

    func showSearch() {
        presentOverlay(AnyView(SearchOverlay(
            store: store,
            currentInbox: { [weak self] in Inbox.parse(self?.textView.string ?? "") },
            onOpenNote: { [weak self] url in self?.openNote(url) },
            onRevealInbox: { [weak self] snippet in self?.revealInInbox(snippet: snippet) }
        )), title: "Search")
    }

    func showLoops() {
        presentOverlay(AnyView(LoopsOverlay(
            store: store,
            currentInbox: { [weak self] in Inbox.parse(self?.textView.string ?? "") },
            onComplete: { [weak self] loop in self?.completeLoop(loop) },
            onJump: { [weak self] loop in
                if loop.fileURL == self?.store.inboxURL {
                    self?.revealInInbox(snippet: "- [ ] " + loop.text)
                } else {
                    self?.openNote(loop.fileURL)
                }
            }
        )), title: "Open loops")
    }

    func showNotes() {
        presentOverlay(AnyView(NotesOverlay(
            store: store,
            onOpen: { [weak self] url in self?.openNote(url) },
            onNew: { [weak self] in self?.newNote() }
        )), title: "Notes")
    }

    private func presentOverlay(_ overlay: AnyView, title: String) {
        closeOverlay()
        headerLabel.stringValue = title
        scrollView.isHidden = true
        let host = NSHostingView(rootView: overlay)
        host.translatesAutoresizingMaskIntoConstraints = false
        stack.insertArrangedSubview(host, at: 1)
        NSLayoutConstraint.activate([
            host.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
        overlayHost = host
    }

    func closeOverlay() {
        if let host = overlayHost {
            stack.removeArrangedSubview(host)
            host.removeFromSuperview()
            overlayHost = nil
        }
        scrollView.isHidden = false
        resetHeader()
    }
}

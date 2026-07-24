// A3 reimagined: shake-to-capture. Start dragging text or a link anywhere,
// jiggle the cursor for a moment, and a calm drop pill fades in top-center.
// Drop on it and the content lands in the inbox. No permissions needed:
// global mouse monitors and the drag pasteboard are both free APIs.
// Built by Claude (Anthropic).

import AppKit

final class DragJiggleCaptureController {
    private let onDrop: (String) -> Bool
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var samples: [(t: TimeInterval, x: CGFloat, y: CGFloat)] = []
    private var window: NSWindow?
    private var lastDragChangeCount: Int
    private var shownForThisDrag = false

    init(onDrop: @escaping (String) -> Bool) {
        self.onDrop = onDrop
        lastDragChangeCount = NSPasteboard(name: .drag).changeCount
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.dragged(event)
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.dragEnded()
        }
    }

    private func dragged(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        let loc = NSEvent.mouseLocation
        samples.append((now, loc.x, loc.y))
        samples.removeAll { now - $0.t > 0.9 }
        guard !shownForThisDrag, isJiggle() else { return }

        // Only react when something is really being dragged: a payload drag
        // advances the drag pasteboard; window moves and clicks do not.
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != lastDragChangeCount else { return }
        let hasString = pasteboard.string(forType: .string) != nil
        let hasURL = ((pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.isEmpty == false)
        guard hasString || hasURL else { return }

        shownForThisDrag = true
        show()
    }

    /// A jiggle: several quick horizontal direction reversals in under a second,
    /// with real travel but staying in a small area.
    private func isJiggle() -> Bool {
        guard samples.count >= 8 else { return false }
        var reversals = 0
        var previousDx: CGFloat = 0
        var path: CGFloat = 0
        for i in 1..<samples.count {
            let dx = samples[i].x - samples[i - 1].x
            path += abs(dx) + abs(samples[i].y - samples[i - 1].y)
            if dx * previousDx < 0, abs(dx) > 3 { reversals += 1 }
            if abs(dx) > 3 { previousDx = dx }
        }
        let xs = samples.map { $0.x }
        let ys = samples.map { $0.y }
        let spanX = (xs.max() ?? 0) - (xs.min() ?? 0)
        let spanY = (ys.max() ?? 0) - (ys.min() ?? 0)
        return reversals >= 4 && path > 120 && spanX < 300 && spanY < 220
    }

    private func show() {
        if let window {
            window.orderFrontRegardless()
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }

        let size = NSSize(width: 280, height: 60)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - 8
        )
        let w = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        w.contentView = DropPillView(
            frame: NSRect(origin: .zero, size: size),
            onDrop: { [weak self] text in
                guard let self else { return false }
                let ok = self.onDrop(text)
                if ok { self.hide(after: 0.7) }
                return ok
            }
        )
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            w.animator().alphaValue = 1
        }
        window = w
    }

    private func dragEnded() {
        shownForThisDrag = false
        samples.removeAll()
        lastDragChangeCount = NSPasteboard(name: .drag).changeCount
        // Give a drop that landed on the pill a beat to run and flash first.
        hide(after: 0.9)
    }

    private func hide(after delay: TimeInterval) {
        guard window != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let w = self.window else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                w.animator().alphaValue = 0
            }, completionHandler: {
                w.orderOut(nil)
                self.window = nil
            })
        }
    }
}

final class DropPillView: NSView {
    private let onDrop: (String) -> Bool

    private enum State { case idle, hover, flash }
    private var state: State = .idle {
        didSet { needsDisplay = true }
    }

    init(frame: NSRect, onDrop: @escaping (String) -> Bool) {
        self.onDrop = onDrop
        super.init(frame: frame)
        registerForDraggedTypes([.string, .URL, .fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let pill = bounds.insetBy(dx: 4, dy: 4)
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)

        let background: NSColor
        let border: NSColor
        let label: String
        let labelColor: NSColor
        switch state {
        case .idle:
            background = Theme.surface.withAlphaComponent(0.97)
            border = Theme.accent.withAlphaComponent(0.55)
            label = "Drop to capture"
            labelColor = Theme.textMuted
        case .hover:
            background = Theme.accent.withAlphaComponent(0.16)
            border = Theme.accent
            label = "Drop to capture"
            labelColor = Theme.text
        case .flash:
            background = Theme.done.withAlphaComponent(0.18)
            border = Theme.done
            label = "✓ captured"
            labelColor = Theme.done
        }

        background.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: labelColor
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let textSize = text.size()
        text.draw(at: NSPoint(x: bounds.midX - textSize.width / 2, y: bounds.midY - textSize.height / 2))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        state = .hover
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        state = .idle
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let string = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []

        var text: String?
        if let string, !string.isEmpty {
            text = string
            if let url = urls.first, !url.isFileURL, url.absoluteString != string {
                text = string + "\nfrom: " + url.absoluteString
            }
        } else if !urls.isEmpty {
            text = urls.map { url in
                url.isFileURL ? url.lastPathComponent + "\nfrom: " + url.path : url.absoluteString
            }.joined(separator: "\n")
        }

        guard let text, onDrop(text) else {
            state = .idle
            return false
        }
        state = .flash
        return true
    }
}

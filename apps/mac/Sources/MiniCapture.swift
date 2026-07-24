// A1: the menu bar mini-capture. A compact field into the same inbox, for
// second displays and moments when the full panel feels heavy.
// Built by Claude (Anthropic).

import AppKit

final class MiniCaptureViewController: NSViewController, NSTextViewDelegate {
    private let capture: (String) -> Bool
    private let onDone: () -> Void
    private var textView: NSTextView!
    private var hint: NSTextField!
    private let defaultHint = "Return captures · Option+Return new line · Esc closes"

    init(capture: @escaping (String) -> Bool, onDone: @escaping () -> Void) {
        self.capture = capture
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 96))

        let scroll = NSScrollView(frame: NSRect(x: 12, y: 32, width: 276, height: 54))
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let tv = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        tv.font = Theme.editorFont
        tv.textColor = Theme.text
        tv.insertionPointColor = Theme.accent
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 2, height: 4)
        tv.autoresizingMask = [.width]
        tv.delegate = self
        scroll.documentView = tv
        textView = tv

        hint = NSTextField(labelWithString: defaultHint)
        hint.font = Theme.metaFont
        hint.textColor = Theme.textMuted
        hint.frame = NSRect(x: 14, y: 9, width: 274, height: 16)
        hint.lineBreakMode = .byTruncatingTail

        root.addSubview(scroll)
        root.addSubview(hint)
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        resetHint()
        view.window?.makeKey()
        view.window?.makeFirstResponder(textView)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onDone()
            return true
        }
        return false
    }

    private func submit() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            onDone()
            return
        }
        if capture(text) {
            textView.string = ""
            hint.stringValue = "✓ captured"
            hint.textColor = Theme.done
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.resetHint()
                self?.onDone()
            }
        } else {
            hint.stringValue = "Could not reach the notes folder just now"
            hint.textColor = Theme.attention
        }
    }

    private func resetHint() {
        hint.stringValue = defaultHint
        hint.textColor = Theme.textMuted
    }
}

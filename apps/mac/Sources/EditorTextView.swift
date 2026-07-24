// The inbox editor: a plain NSTextView with live Markdown styling and clickable
// checkboxes. Raw text stays raw on disk; the styling is presentation only.
// Built by Claude (Anthropic).

import AppKit
#if canImport(LedgeCore)
import LedgeCore
#endif

final class EditorTextView: NSTextView {
    var onCheckboxToggle: (() -> Void)?

    static func make() -> EditorTextView {
        let textView = EditorTextView(frame: .zero)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = Theme.editorFont
        textView.textColor = Theme.text
        textView.insertionPointColor = Theme.accent
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.selectedTextAttributes = [
            .backgroundColor: Theme.accent.withAlphaComponent(0.2)
        ]
        return textView
    }

    /// Click on the bracket part of "- [ ]" or "- [x]" toggles it in place.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let ns = string as NSString
        if index < ns.length || (index > 0 && index == ns.length) {
            let probe = min(index, max(0, ns.length - 1))
            let lineRange = ns.lineRange(for: NSRange(location: probe, length: 0))
            let line = ns.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isOpen = trimmed.hasPrefix("- [ ]")
            let isDone = trimmed.hasPrefix("- [x]")
            if isOpen || isDone {
                // The clickable zone: from line start through the closing bracket.
                if let bracket = line.range(of: "]") {
                    let bracketEnd = line.distance(from: line.startIndex, to: bracket.upperBound)
                    let zone = NSRange(location: lineRange.location, length: bracketEnd)
                    if index >= zone.location && index <= zone.location + zone.length {
                        toggleCheckbox(inLine: lineRange, line: line, currentlyOpen: isOpen)
                        return
                    }
                }
            }
        }
        super.mouseDown(with: event)
    }

    private func toggleCheckbox(inLine lineRange: NSRange, line: String, currentlyOpen: Bool) {
        let from = currentlyOpen ? "[ ]" : "[x]"
        let to = currentlyOpen ? "[x]" : "[ ]"
        guard let localRange = line.range(of: from) else { return }
        let start = line.distance(from: line.startIndex, to: localRange.lowerBound)
        let target = NSRange(location: lineRange.location + start, length: 3)
        if shouldChangeText(in: target, replacementString: to) {
            textStorage?.replaceCharacters(in: target, with: to)
            didChangeText()
        }
        MarkdownStyler.style(self)
        onCheckboxToggle?()
    }
}

/// One full styling pass. Inbox files stay small (the Attic guarantees it), so a
/// whole-document pass on a debounce is simple and fast enough.
enum MarkdownStyler {
    static func style(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: ns.length)

        let body = NSMutableParagraphStyle()
        body.lineHeightMultiple = 1.35
        body.paragraphSpacing = 2

        storage.beginEditing()
        storage.setAttributes([
            .font: Theme.editorFont,
            .foregroundColor: Theme.text,
            .paragraphStyle: body
        ], range: full)

        ns.enumerateSubstrings(in: full, options: [.byLines]) { substring, lineRange, _, _ in
            guard let line = substring else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if LedgeFormatBridge.isDayHeader(line) {
                storage.addAttributes([
                    .font: Theme.dayFont,
                    .foregroundColor: Theme.textMuted
                ], range: lineRange)
            } else if LedgeFormatBridge.isEntryHeader(line) {
                storage.addAttributes([
                    .font: Theme.metaFont,
                    .foregroundColor: Theme.textAged
                ], range: lineRange)
            } else if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
                storage.addAttributes([
                    .font: NSFont.systemFont(ofSize: trimmed.hasPrefix("# ") ? 18 : 15, weight: .semibold)
                ], range: lineRange)
            } else if trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("* [x]") {
                storage.addAttributes([
                    .foregroundColor: Theme.textAged,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ], range: lineRange)
            } else if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("* [ ]") {
                if let bracket = line.range(of: "- [ ]") ?? line.range(of: "* [ ]") {
                    let start = line.distance(from: line.startIndex, to: bracket.lowerBound)
                    let markerRange = NSRange(location: lineRange.location + start, length: 5)
                    storage.addAttributes([.foregroundColor: Theme.accent], range: markerRange)
                }
            } else if trimmed.hasPrefix("> ") {
                storage.addAttributes([.foregroundColor: Theme.textMuted], range: lineRange)
            }
        }

        applyInline(pattern: "\\*\\*[^*\\n]+\\*\\*", storage: storage, ns: ns) { range in
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 15, weight: .semibold)], range: range)
        }
        applyInline(pattern: "`[^`\\n]+`", storage: storage, ns: ns) { range in
            storage.addAttributes([
                .font: Theme.codeFont,
                .backgroundColor: Theme.surface2
            ], range: range)
        }

        storage.endEditing()
    }

    private static func applyInline(pattern: String, storage: NSTextStorage, ns: NSString, _ apply: (NSRange) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let full = NSRange(location: 0, length: ns.length)
        regex.enumerateMatches(in: storage.string, options: [], range: full) { match, _, _ in
            if let range = match?.range { apply(range) }
        }
    }
}

/// Thin bridge so the styler matches exactly what the parser recognizes.
enum LedgeFormatBridge {
    static func isDayHeader(_ line: String) -> Bool { LedgeFormat.isDayHeader(line) }
    static func isEntryHeader(_ line: String) -> Bool { LedgeFormat.isEntryHeader(line) }
}

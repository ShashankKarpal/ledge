// Paste as Markdown: rich pasteboard content lands as clean Markdown instead of
// flattened plain text. Links survive, bold survives, lists survive, images are
// filed into assets/ and referenced. Plain text passes through untouched.
// Built by Claude (Anthropic).

import AppKit

enum PasteMarkdown {
    /// Markdown for the current pasteboard, or nil when a plain paste is the
    /// right thing (pure text, or rich text with no structure worth keeping).
    static func markdown(from pb: NSPasteboard, assetsDirectory: URL?) -> String? {
        if let assets = assetsDirectory, let imageRef = imageMarkdown(from: pb, into: assets) {
            return imageRef
        }

        var attributed: NSAttributedString?
        if let rtf = pb.data(forType: .rtf) {
            attributed = NSAttributedString(rtf: rtf, documentAttributes: nil)
        }
        if attributed == nil, let html = pb.data(forType: .html) {
            attributed = try? NSAttributedString(
                data: html,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
        }
        guard let rich = attributed, rich.length > 0 else { return nil }

        let converted = markdown(from: rich)
        let plain = (pb.string(forType: .string) ?? rich.string)
        let normalizedConverted = converted.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPlain = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        // No structure gained: stay out of the way.
        return normalizedConverted == normalizedPlain ? nil : normalizedConverted
    }

    // MARK: Images

    private static func imageMarkdown(from pb: NSPasteboard, into assets: URL) -> String? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let images = urls.filter { isImagePath($0) }
            guard !images.isEmpty else { return nil }
            let refs = images.compactMap { copyImage(at: $0, into: assets) }
            return refs.isEmpty ? nil : refs.joined(separator: "\n")
        }
        if pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil {
            return savePasteboardImage(pb, into: assets)
        }
        return nil
    }

    private static func isImagePath(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"].contains(url.pathExtension.lowercased())
    }

    private static func copyImage(at url: URL, into assets: URL) -> String? {
        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let name = "paste-" + stamp() + "-" + url.lastPathComponent
        let dest = assets.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return "![\(url.deletingPathExtension().lastPathComponent)](assets/\(name))"
        } catch {
            return nil
        }
    }

    private static func savePasteboardImage(_ pb: NSPasteboard, into assets: URL) -> String? {
        guard let image = NSImage(pasteboard: pb),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let name = "paste-" + stamp() + ".png"
        do {
            try png.write(to: assets.appendingPathComponent(name))
            return "![pasted image](assets/\(name))"
        } catch {
            return nil
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: Attributed string to Markdown

    static func markdown(from attributed: NSAttributedString) -> String {
        var lines: [String] = []
        let ns = attributed.string as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let paragraph = attributed.attributedSubstring(from: range)
            lines.append(markdownParagraph(paragraph))
        }
        // Collapse runs of blank lines left behind by HTML spacing.
        var out: [String] = []
        var blankRun = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun += 1
                if blankRun <= 1 { out.append("") }
            } else {
                blankRun = 0
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    private static func markdownParagraph(_ paragraph: NSAttributedString) -> String {
        guard paragraph.length > 0 else { return "" }
        var out = ""
        let ns = paragraph.string as NSString
        paragraph.enumerateAttributes(in: NSRange(location: 0, length: paragraph.length), options: []) { attrs, range, _ in
            var piece = ns.substring(with: range)
            guard !piece.isEmpty else { return }
            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            if !piece.trimmingCharacters(in: .whitespaces).isEmpty {
                if traits.contains(.monoSpace) {
                    piece = wrap(piece, "`")
                } else {
                    if traits.contains(.bold) { piece = wrap(piece, "**") }
                    if traits.contains(.italic) { piece = wrap(piece, "*") }
                }
                if let link = attrs[.link] {
                    let urlString = (link as? URL)?.absoluteString ?? "\(link)"
                    piece = linked(piece, url: urlString)
                }
            }
            out += piece
        }

        var line = out
        let hadBullet = stripLeadingBullet(&line)
        let style = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let inTextList = !(style?.textLists.isEmpty ?? true)
        if hadBullet || inTextList {
            let core = line.trimmingCharacters(in: .whitespaces)
            return core.isEmpty ? "" : "- " + core
        }
        return line
    }

    /// Cocoa's HTML importer renders list items as "\t•\tcontent". Strip that
    /// so it can become a Markdown bullet instead.
    private static func stripLeadingBullet(_ line: inout String) -> Bool {
        let markers: [Character] = ["\u{2022}", "\u{25E6}", "\u{2023}", "\u{2043}"]
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard let first = trimmed.first, markers.contains(first) else { return false }
        line = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        return true
    }

    /// Markers hug the content; leading and trailing whitespace stays outside.
    private static func wrap(_ text: String, _ marker: String) -> String {
        let leading = String(text.prefix { $0 == " " || $0 == "\t" })
        let trailing = String(String(text.reversed()).prefix { $0 == " " || $0 == "\t" })
        let core = text.dropFirst(leading.count).dropLast(trailing.count)
        guard !core.isEmpty else { return text }
        return leading + marker + core + marker + trailing
    }

    private static func linked(_ text: String, url: String) -> String {
        let leading = String(text.prefix { $0 == " " || $0 == "\t" })
        let trailing = String(String(text.reversed()).prefix { $0 == " " || $0 == "\t" })
        let core = String(text.dropFirst(leading.count).dropLast(trailing.count))
        guard !core.isEmpty else { return text }
        // A bare URL pasted as its own link stays a bare URL.
        if core == url || core == url.replacingOccurrences(of: "https://", with: "")
            || core == url.replacingOccurrences(of: "http://", with: "") {
            return leading + url + trailing
        }
        return leading + "[" + core + "](" + url + ")" + trailing
    }
}

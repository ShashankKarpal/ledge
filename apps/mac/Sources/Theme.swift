// Design tokens from design/tokens.json, as dynamic colors (light and dark).
// Rules: one accent, no red anywhere, age fades instead of flagging.
// Built by Claude (Anthropic).

import AppKit

enum Theme {
    static func dynamic(light: String, dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    static let bg = dynamic(light: "#F3F1EB", dark: "#0B0C0D")
    static let surface = dynamic(light: "#FFFFFF", dark: "#171614")
    static let surface2 = dynamic(light: "#EDEBE6", dark: "#201E1B")
    static let text = dynamic(light: "#0B0C0D", dark: "#F3F1EB")
    static let textMuted = dynamic(light: "#6D6774", dark: "#C4C6CA")
    static let textAged = dynamic(light: "#9B95A1", dark: "#8E8F94")
    static let border = dynamic(light: "#E2E0DA", dark: "#292826")
    static let accent = dynamic(light: "#99612F", dark: "#B17E51")
    static let done = dynamic(light: "#307A64", dark: "#4FC4A6")
    static let attention = dynamic(light: "#695725", dark: "#E0B93A")

    static let editorFont = NSFont.systemFont(ofSize: 15)
    static let metaFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let dayFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static let panelRadius: CGFloat = 12
    static let slideDuration: TimeInterval = 0.16
}

extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

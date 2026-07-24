// Ledge colors, generated from design/tokens.json (v1.1). Light and dark
// resolve through UIColor dynamic providers. No red states anywhere.
// Built by Claude (Anthropic).

import SwiftUI
import UIKit

private extension UIColor {
    convenience init(hex: String) {
        var cleaned = hex
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((value & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(value & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }

    static func ledgeDynamic(light: String, dark: String) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }
}

extension Color {
    static let ledgeBg = Color(uiColor: .ledgeDynamic(light: "#F7F5F2", dark: "#1C1B1D"))
    static let ledgeSurface = Color(uiColor: .ledgeDynamic(light: "#FCFBF8", dark: "#28272A"))
    static let ledgeText = Color(uiColor: .ledgeDynamic(light: "#1C1B1D", dark: "#F7F5F2"))
    static let ledgeTextMuted = Color(uiColor: .ledgeDynamic(light: "#6D6774", dark: "#C4C6CA"))
    static let ledgeAccent = Color(uiColor: .ledgeDynamic(light: "#BD4753", dark: "#E78892"))
    static let ledgeDone = Color(uiColor: .ledgeDynamic(light: "#367B23", dark: "#A0D392"))
    static let ledgeAttention = Color(uiColor: .ledgeDynamic(light: "#C28A0F", dark: "#E8B13B"))
    static let ledgeAged = Color(uiColor: .ledgeDynamic(light: "#9B95A1", dark: "#8E8F94"))
}

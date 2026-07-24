// Settings live in .ledge/settings.json. Unknown keys written by other tools are preserved.
// Built by Claude (Anthropic).

import Foundation

public struct HotkeySetting: Codable, Equatable {
    /// Carbon virtual key code. 49 is Space.
    public var keyCode: UInt32
    /// One of: "option", "control", "command", "optionControl", "optionCommand".
    public var modifiers: String

    public init(keyCode: UInt32 = 49, modifiers: String = "option") {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct LedgeSettings: Equatable {
    public var panelWidth: Double
    public var agingDays: Int
    public var hotkey: HotkeySetting
    public var theme: String

    public static let defaults = LedgeSettings(
        panelWidth: 380,
        agingDays: 30,
        hotkey: HotkeySetting(),
        theme: "system"
    )

    public init(panelWidth: Double, agingDays: Int, hotkey: HotkeySetting, theme: String) {
        self.panelWidth = min(max(panelWidth, 320), 520)
        self.agingDays = agingDays
        self.hotkey = hotkey
        self.theme = theme
    }

    public static func load(from url: URL) -> LedgeSettings {
        guard let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .defaults
        }
        var settings = LedgeSettings.defaults
        if let width = json["panelWidth"] as? Double { settings.panelWidth = min(max(width, 320), 520) }
        if let width = json["panelWidth"] as? Int { settings.panelWidth = min(max(Double(width), 320), 520) }
        if let days = json["agingDays"] as? Int { settings.agingDays = days }
        if let theme = json["theme"] as? String { settings.theme = theme }
        if let hotkey = json["hotkey"] as? [String: Any] {
            if let code = hotkey["keyCode"] as? Int { settings.hotkey.keyCode = UInt32(code) }
            if let mods = hotkey["modifiers"] as? String { settings.hotkey.modifiers = mods }
        }
        return settings
    }

    /// Merge-write: keys this version does not know about are kept intact.
    public func save(to url: URL) throws {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            json = existing
        }
        json["panelWidth"] = panelWidth
        json["agingDays"] = agingDays
        json["theme"] = theme
        json["hotkey"] = ["keyCode": Int(hotkey.keyCode), "modifiers": hotkey.modifiers]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

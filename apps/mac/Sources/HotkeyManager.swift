// Global hotkey via Carbon RegisterEventHotKey: the only public API that needs
// zero privacy permissions. Deprecated for a decade, relied on by everyone.
// Built by Claude (Anthropic).

import AppKit
import Carbon.HIToolbox
#if canImport(LedgeCore)
import LedgeCore
#endif

final class HotkeyManager {
    var onHotkey: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func register(_ setting: HotkeySetting) {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onHotkey?() }
            return noErr
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C44_4745), id: 1) // "LDGE"
        RegisterEventHotKey(
            setting.keyCode,
            Self.carbonModifiers(setting.modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    static func carbonModifiers(_ name: String) -> UInt32 {
        switch name {
        case "control": return UInt32(controlKey)
        case "command": return UInt32(cmdKey)
        case "optionControl": return UInt32(optionKey | controlKey)
        case "optionCommand": return UInt32(optionKey | cmdKey)
        default: return UInt32(optionKey)
        }
    }

    static func describe(_ setting: HotkeySetting) -> String {
        let mods: String
        switch setting.modifiers {
        case "control": mods = "⌃"
        case "command": mods = "⌘"
        case "optionControl": mods = "⌥⌃"
        case "optionCommand": mods = "⌥⌘"
        default: mods = "⌥"
        }
        let key = setting.keyCode == 49 ? "Space" : "key \(setting.keyCode)"
        return mods + key
    }
}

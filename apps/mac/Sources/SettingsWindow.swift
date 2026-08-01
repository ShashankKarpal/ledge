// Settings, finally a window instead of hand-editing settings.json.
// Every change saves immediately through the merge-write, so keys written by
// other tools survive. Built by Claude (Anthropic).

import AppKit
import SwiftUI
import ServiceManagement
#if canImport(LedgeCore)
import LedgeCore
#endif

final class SettingsWindowController: NSWindowController {
    convenience init(settings: LedgeSettings, onChange: @escaping (LedgeSettings) -> Void) {
        let hosting = NSHostingController(rootView: SettingsView(initial: settings, onChange: onChange))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Ledge Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 240))
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

struct SettingsView: View {
    @State private var width: Double
    @State private var agingDays: Int
    @State private var hotkeyModifiers: String
    @State private var launchAtLogin: Bool
    private let theme: String
    private let onChange: (LedgeSettings) -> Void

    private static let hotkeyChoices: [(label: String, modifiers: String)] = [
        ("Option + Space", "option"),
        ("Control + Space", "control"),
        ("Option + Command + Space", "optionCommand"),
        ("Option + Control + Space", "optionControl")
    ]

    init(initial: LedgeSettings, onChange: @escaping (LedgeSettings) -> Void) {
        _width = State(initialValue: initial.panelWidth)
        _agingDays = State(initialValue: initial.agingDays)
        _hotkeyModifiers = State(initialValue: initial.hotkey.modifiers)
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
        self.theme = initial.theme
        self.onChange = onChange
    }

    var body: some View {
        Form {
            Picker("Summon hotkey", selection: $hotkeyModifiers) {
                ForEach(Self.hotkeyChoices, id: \.modifiers) { choice in
                    Text(choice.label).tag(choice.modifiers)
                }
            }
            .onChange(of: hotkeyModifiers) { _ in emit() }

            VStack(alignment: .leading, spacing: 2) {
                Slider(value: $width, in: 320...520, step: 10) {
                    Text("Panel width")
                }
                .onChange(of: width) { _ in emit() }
                Text("\(Int(width)) points")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: Theme.textAged))
            }

            Stepper(value: $agingDays, in: 7...120) {
                Text("Days before entries rest in the Attic: \(agingDays)")
            }
            .onChange(of: agingDays) { _ in emit() }

            Toggle("Start Ledge at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        // Quiet by design; the toggle reflects reality next open.
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Text("Changes apply immediately. Nothing here touches your notes.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: Theme.textAged))
        }
        .padding(20)
        .frame(width: 400)
    }

    private func emit() {
        onChange(LedgeSettings(
            panelWidth: width,
            agingDays: agingDays,
            hotkey: HotkeySetting(keyCode: 49, modifiers: hotkeyModifiers),
            theme: theme
        ))
    }
}

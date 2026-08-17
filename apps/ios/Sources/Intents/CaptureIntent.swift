// Shortcuts and Siri capture. Writes to the spool (capture/drop.md), the safe
// path for out-of-app writers, never straight into inbox.md. Works even when
// the app's 7-day free signing has expired, as long as iOS can still run the
// intent in the background.
// Built by Claude (Anthropic).

import Foundation
import AppIntents

struct CaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture to Ledge"
    static var description = IntentDescription("Adds a thought to your Ledge inbox.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Thought", requestValueDialog: "What's the thought?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SpoolWriter.append(text: text, at: Date(), device: "iPhone")
        return .result(dialog: "Captured.")
    }
}

struct LedgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Capture to \(.applicationName)",
                "Capture my thought in \(.applicationName)",
                "Capture a thought in \(.applicationName)",
                "Capture my thought with \(.applicationName)",
                "Add a thought to \(.applicationName)",
                "\(.applicationName), capture my thought"
            ],
            shortTitle: "Capture",
            systemImageName: "square.and.pencil"
        )
    }
}

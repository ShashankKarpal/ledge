// Siri and Shortcuts capture, compiled into BOTH the iPhone app and the
// watch app (see the LedgeWatch sources list in project.yml).
// iPhone: writes to the spool (capture/drop.md), the safe path for
// out-of-app writers, never straight into inbox.md; falls back to a local
// pending queue, so capture never fails.
// Watch: the watch cannot reach the iCloud folder, so the intent hands the
// thought to the WatchConnectivity relay, whose queued transfer delivers
// even when the iPhone is unreachable. Capture never fails there either.
// Built by Claude (Anthropic).

import Foundation
import AppIntents
#if os(watchOS)
import LedgeCore
#endif

struct CaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture to Ledge"
    static var description = IntentDescription("Adds a thought to your Ledge inbox.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Thought", requestValueDialog: "What's the thought?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if os(watchOS)
        let trimmed = LedgeFormat.trimEdges(text)
        if !trimmed.isEmpty {
            WatchSessionManager.shared.send(trimmed)
        }
        #else
        SpoolWriter.append(text: text, at: Date(), device: "iPhone")
        #endif
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

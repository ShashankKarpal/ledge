// Ledge for Apple Watch: one purpose, capture.
// Built by Claude (Anthropic).

import SwiftUI

@main
struct LedgeWatchApp: App {
    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            CaptureView()
        }
    }
}

// Ledge for iOS: an ADHD-first notepad. The folder is the database.
// Built by Claude (Anthropic).

import SwiftUI

@main
struct LedgeApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Start listening for watch captures as early as possible.
        SessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Color.ledgeAccent)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        model.becameActive()
                        model.startHeartbeat()
                    } else {
                        model.stopHeartbeat()
                    }
                }
        }
    }
}

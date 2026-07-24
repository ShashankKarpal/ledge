// Ledge for iOS: an ADHD-first notepad. The folder is the database.
// Built by Claude (Anthropic).

import SwiftUI

extension Notification.Name {
    /// Posted when a widget or the Control Center control asks for the capture keyboard.
    static let ledgeFocusCapture = Notification.Name("ledgeFocusCapture")
}

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
                .onOpenURL { url in
                    guard url.scheme == "ledge" else { return }
                    NotificationCenter.default.post(name: .ledgeFocusCapture, object: nil)
                }
        }
    }
}

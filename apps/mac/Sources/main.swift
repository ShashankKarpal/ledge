// Ledge for Mac: entry point. Menu bar app, no Dock icon, no windows until summoned.
// Built by Claude (Anthropic).

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

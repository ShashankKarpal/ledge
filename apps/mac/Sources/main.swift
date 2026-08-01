// Ledge for Mac: entry point. Menu bar app, no Dock icon, no windows until summoned.
// Built by Claude (Anthropic).

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

// Key equivalents (Cmd+V, Cmd+C, Cmd+X, Cmd+A, Cmd+Z) are routed through the
// main menu, even for accessory apps whose menu bar is never visible. Without
// an Edit menu, paste and friends silently do nothing anywhere in the app.
let mainMenu = NSMenu()

let appMenuItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit Ledge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)

let editMenuItem = NSMenuItem()
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
redoItem.keyEquivalentModifierMask = [.command, .shift]
editMenu.addItem(redoItem)
editMenu.addItem(NSMenuItem.separator())
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editMenuItem.submenu = editMenu
mainMenu.addItem(editMenuItem)

app.mainMenu = mainMenu
app.run()

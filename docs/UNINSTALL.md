# Uninstalling Ledge

Ledge keeps your notes in a folder you own and never inside the app, so
removing the app removes nothing you wrote. Every step below is reversible
except the last, which is deliberately separate.

## Mac

1. Quit Ledge: right-click the menu bar glyph, Quit Ledge (or `osascript -e
   'tell application "Ledge" to quit'`).
2. Remove the app:

       rm -rf /Applications/Ledge.app

3. Remove the settings that macOS keeps for it (hotkey choice, panel width,
   the "start at login" registration goes with the app):

       defaults delete com.shashankkarpal.ledge.mac

4. Optional: remove the local safety copies. These live OUTSIDE your notes
   folder on purpose and hold copies of your text: the write-ahead capture
   log, the editor recovery journal, and the dated backups of `inbox.md`.
   Look before you delete.

       open ~/Library/Application\ Support/Ledge     # look first
       rm -rf ~/Library/Application\ Support/Ledge   # then, if you are sure

If you installed through Homebrew: `brew uninstall --cask ledge` does steps 1
to 3, and `brew uninstall --cask --zap ledge` adds step 4.

## iPhone, iPad, Apple Watch

Delete the app from the Home Screen as you would any other. Its only local
state is a folder bookmark, a small pending-captures queue, and the
per-device capture log; all of it goes with the app. The Watch app goes with
the iPhone app.

## Your notes

Your notes are the `Ledge` folder in iCloud Drive (or `~/Documents/Ledge` if
you chose a local folder): `inbox.md`, `attic/`, `notes/`, `assets/`,
`capture/`, and a small `.ledge/` folder of settings, heartbeats and the
content-free incident log. Nothing above touches it. Keep it, open it in any
Markdown editor, or delete it yourself when you are certain.

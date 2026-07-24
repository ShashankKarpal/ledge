# Ledge for iOS and Apple Watch

The iOS companion to the Ledge Mac app, plus a one-screen watch capture relay. Everything is plain Markdown in a folder you pick; see `docs/file-format.md` at the repo root for the contract.

## Build

1. Install XcodeGen (once):

   ```
   brew install xcodegen
   ```

2. Generate the project from this directory (`apps/ios`):

   ```
   xcodegen generate
   ```

3. Open it:

   ```
   open Ledge.xcodeproj
   ```

4. In Xcode, select the project, then set your Team on **both** targets (Ledge and LedgeWatch) under Signing and Capabilities. A free personal team works fine.

5. **Change the bundle identifiers.** They ship as `com.example.ledge` and `com.example.ledge.watchkitapp`, and free personal teams must use identifiers nobody else has claimed. Edit `project.yml` (recommended, then re-run `xcodegen generate`) or change them in Xcode:
   - iOS app: `com.yourname.ledge` (anything unique)
   - Watch app: `com.yourname.ledge.watchkitapp` (must be the iOS id plus `.watchkitapp`)
   - Also update `WKCompanionAppBundleIdentifier` in the LedgeWatch target's info so it matches your new iOS id. In `project.yml` these live next to each other, marked with comments.

6. Plug in your iPhone, pick it as the run destination, and run the Ledge scheme. The watch app installs alongside it when a paired watch is available (or run the LedgeWatch scheme directly on the watch).

### Developer Mode

The first deploy to a physical device needs Developer Mode: on the iPhone, Settings, Privacy and Security, Developer Mode, turn it on, restart. Same idea on the watch: Settings, Privacy and Security, Developer Mode.

## First launch

Ledge asks you to pick a folder. Create a folder named `Ledge` in iCloud Drive (Files app, iCloud Drive, New Folder) and pick that one; your Mac app can then point at the same folder and both stay in sync through iCloud. Any folder works, but iCloud Drive is what makes the Mac and iPhone share.

Ledge creates `inbox.md`, `notes/`, `attic/`, and `capture/drop.md` inside it on first open.

## The 7-day free signing window

Apps signed with a free personal team expire after 7 days; after that the app icon stops launching until you plug in and run from Xcode again. Two things soften this:

- Captures via Shortcuts and Siri ("Capture to Ledge") keep working even when the app itself has expired, because App Intents run in the background without launching the UI. Your thoughts pile up safely in `capture/drop.md` and fold into the inbox the next time the app opens.
- Nothing is ever lost: the folder is the database, and the Mac app keeps working with the same files regardless.

If you have a paid Apple Developer membership, signing lasts a year and none of this applies.

## Removing the watch app

If the LedgeWatch target blocks your build (no paired watch, or signing friction), open `project.yml` and delete:

1. The block from `# LedgeWatch target BEGIN` to `# LedgeWatch target END`.
2. The two lines between `# LedgeWatch embed BEGIN` and `# LedgeWatch embed END` in the Ledge target's dependencies.

Then run `xcodegen generate` again. The iOS app builds cleanly without it.

## Troubleshooting

- **"Ledge lost access to your folder."** iOS revokes folder permission if the folder is moved, renamed, or deleted, and occasionally after a restore. Tap the folder icon in the toolbar (it appears only when the connection is broken) and pick the folder again. Your files are untouched.
- **Inbox looks empty or a note opens blank.** iCloud keeps rarely-used files "dataless" until something reads them. The first read triggers a download, which can take a moment on slow connections. Pull to refresh on the inbox, or reopen the note; once downloaded it stays local.
- **Watch captures not arriving.** They queue on the watch (you will see "2 waiting for iPhone" in muted text) and deliver when the phone is nearby with Bluetooth on. Opening the Ledge iOS app then folds them into the inbox. Nothing expires and nothing is dropped.
- **Changed the bundle id and Siri stopped responding to "Capture to Ledge".** Run the app once from Xcode; iOS re-registers App Shortcuts on launch.

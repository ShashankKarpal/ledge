// Append one spool line to capture/drop.md under NSFileCoordinator, the same
// lock both Ledge apps take. Used by scripts/deploy.sh to write its probe.
//
// Why this exists: a bare shell append can land in the middle of a drain,
// which truncates exactly the bytes it consumed and would swallow a probe
// appended a moment earlier (independent review, 2026-09-03). Writing in
// place, never atomically, also preserves the file's identity, because the
// Shortcuts "Append to Text File" action holds an out-of-process bookmark to
// it and an atomic replace orphans that bookmark (incident 2026-07-27).
//
// Usage: osascript -l JavaScript scripts/spool-append.js <drop.md path> <line>
// Exit 0 on success, 1 on any failure. Prints nothing on success.
// Built by Claude (Anthropic).

ObjC.import('Foundation');

function run(argv) {
    // Failure must THROW: osascript prints a returned value and still exits 0,
    // so `return 1` would look like success to the shell.
    if (argv.length < 2) {
        throw new Error('usage: spool-append.js <path> <line>');
    }
    const path = argv[0];
    const line = argv[1];

    const url = $.NSURL.fileURLWithPath(path);
    // plain init, not initWithFilePresenter: JXA turns a null argument into
    // NSNull, which NSFileCoordinator then messages as a presenter.
    const coordinator = $.NSFileCoordinator.alloc.init;
    const err = Ref();
    let wrote = false;

    coordinator.coordinateWritingItemAtURLOptionsErrorByAccessor(url, 0, err, function (actual) {
        const actualPath = ObjC.unwrap(actual.path);

        // Read what is there first, as a JS string, so the separator decision
        // never depends on an ObjC return value being usable as a number.
        const existing = $.NSString.stringWithContentsOfFileEncodingError(
            actualPath, $.NSUTF8StringEncoding, null
        );
        const text = existing.isNil() ? '' : ObjC.unwrap(existing);
        const needsSeparator = text.length > 0 && text.charAt(text.length - 1) !== '\n';
        const payload = (needsSeparator ? '\n' : '') + line + '\n';
        const data = $.NSString.stringWithString(payload)
            .dataUsingEncoding($.NSUTF8StringEncoding);

        const handle = $.NSFileHandle.fileHandleForWritingAtPath(actualPath);
        if (handle.isNil()) {
            // No file yet. Creating it is the only case where a whole-file
            // write is correct.
            wrote = data.writeToFileAtomically(actualPath, false);
            return;
        }

        // APPEND, never truncate-then-rewrite. The spool can hold captures no
        // device has folded yet; truncating first opens a window where a
        // crash or a failed write leaves the file empty and those captures
        // are gone. Appending also preserves the inode, which the Shortcuts
        // action's out-of-process bookmark depends on (incident 2026-07-27).
        // Self review, 2026-09-03.
        handle.seekToEndOfFile;
        handle.writeData(data);
        handle.synchronizeFile;
        handle.closeFile;
        wrote = true;
    });

    if (!err[0].isNil() || !wrote) {
        throw new Error('coordinated append failed for ' + path);
    }
}

/**
 * @file PendingAddsInbox
 * @description Generic cross-process text inbox. Polls a file on disk
 *   every pollIntervalMs. When the file has new non-empty lines, emits
 *   linesReceived(lines) — handlers run synchronously — then truncates
 *   the file. Reusable for any "writer appends, we pick up" pattern.
 *
 *   In HomeSpike: the patched Lomiri Drawer.qml appends an appId when the
 *   user picks "Add to HomeSpike" from the long-press menu. We pick up
 *   those appIds and place them on the home grid.
 *
 * @status Stable.
 * @issues Small race window — if the writer appends BETWEEN our read and
 *   our truncate, those lines get lost. Acceptable for the manual long-
 *   press-add UX (one app at a time, well-spaced). Switch to a filename-
 *   per-message scheme if write rate ever grows.
 * @todo None
 */
import QtQuick 2.15

Item {
    id: root

    /** Absolute path of the inbox file to poll. */
    property string filePath: ""

    /** Poll interval in milliseconds. */
    property int pollIntervalMs: 1500

    /**
     * Emitted when the inbox has at least one non-empty line. Handlers
     * run synchronously; the file is truncated immediately after.
     *
     * @param lines Array of trimmed, non-empty lines from the file
     */
    signal linesReceived(var lines)

    Timer {
        interval: root.pollIntervalMs
        repeat: true
        running: root.filePath !== ""
        onTriggered: root.pollNow()
    }

    /**
     * Read and process the inbox immediately, outside the timer cycle.
     * Useful at app startup to drain anything written while we were down.
     */
    function pollNow() {
        if (!filePath) return;
        var content = _readFile();
        if (!content) return;
        var lines = _parseLines(content);
        if (lines.length === 0) {
            _truncate();
            return;
        }
        root.linesReceived(lines);
        _truncate();
    }

    /**
     * Read inbox file contents. Returns "" if the file is missing or
     * unreadable. Intentionally silent on missing-file — the installer
     * creates it but a stale dev environment may not have it yet, and
     * logging every poll would spam the journal.
     */
    function _readFile() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + filePath, false);
        try {
            xhr.send();
            return xhr.responseText || "";
        } catch (e) {
            return "";
        }
    }

    /**
     * Split raw file content into trimmed, non-empty lines.
     */
    function _parseLines(content) {
        var raw = content.split("\n");
        var lines = [];
        for (var i = 0; i < raw.length; ++i) {
            var trimmed = raw[i].replace(/^\s+|\s+$/g, "");
            if (trimmed.length > 0) lines.push(trimmed);
        }
        return lines;
    }

    /**
     * Write empty content to clear the inbox.
     */
    function _truncate() {
        var xhr = new XMLHttpRequest();
        xhr.open("PUT", "file://" + filePath, false);
        try {
            xhr.send("");
        } catch (e) {
            console.error("PendingAddsInbox._truncate: failed to truncate " + filePath + " — " + e);
        }
    }
}

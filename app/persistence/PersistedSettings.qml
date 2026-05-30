/**
 * @file PersistedSettings
 * @description Owns the on-disk Qt.labs.Settings store for HomeSpike and
 *   exposes typed JSON helpers. Persistence happens only when a caller
 *   explicitly assigns to a property — no auto-save loops, no debouncers.
 *   Lives in ~/.config/home-spike/home-spike.conf.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Qt.labs.settings 1.0

Item {
    id: root

    Settings {
        id: store
        // Pinned filename: now that HomeSpike runs inside the lomiri process
        // (Option A — see CLAUDE memory), the default Qt.labs.Settings file
        // would be ~/.config/lomiri/lomiri.conf and our state would mix with
        // Lomiri's. Keep our own file separate.
        fileName: "/home/phablet/.config/home-spike/home-spike.conf"
        category: "homeSpike"
        // pageData is a JSON array — one element per page. Each element is
        // a per-mode bag holding ALL three layouts so users can switch
        // placementMode without losing the previous mode's layout:
        //   [
        //     { autoFill: [appId, ...],
        //       snap:     [{appId, col, row}, ...],
        //       free:     [{appId, xFrac, yFrac}, ...] },
        //     ...
        //   ]
        // Legacy shape `[[appId,...],...]` is migrated into .autoFill on read.
        property string pageData:     '[{"autoFill":[],"snap":[],"free":[]}]'
        property int    pageCount:    1
        property string hiddenAppIds: "[]"
        property string dockOrder:    "[]"
        property bool   dockEnabled:  false
        // Height of the visible dock background plate, in grid units.
        // 1.0 ≈ a thin line under the icons; 12.0 wraps the icons fully.
        property real   dockBgHeight: 12.0
        // Active tile layout. "autoFill" = current left-to-right reflow;
        // "snap" = icons sit on a grid but can leave gaps; "free" = icons
        // are positioned anywhere (fractional coords) and may overlap.
        property string placementMode: "autoFill"
    }

    // ---- Read/write aliases so callers can bind to and mutate values
    //      without poking the underlying Settings object directly. ----
    property alias pageData:      store.pageData
    property alias pageCount:     store.pageCount
    property alias hiddenAppIds:  store.hiddenAppIds
    property alias dockOrder:     store.dockOrder
    property alias dockEnabled:   store.dockEnabled
    property alias dockBgHeight:  store.dockBgHeight
    property alias placementMode: store.placementMode

    /**
     * Parse a JSON string with a fallback. Used to read array values
     * that QSettings persists as strings.
     *
     * @param jsonString String previously produced by writeJson
     * @param fallback   Value to return if parsing fails or input is empty
     * @returns          Parsed value or fallback
     */
    function readJson(jsonString, fallback) {
        try {
            return JSON.parse(jsonString);
        } catch (e) {
            console.error("PersistedSettings.readJson: failed to parse '" + jsonString + "' — " + e);
            return fallback;
        }
    }

    /**
     * Serialize a value to a JSON string for storage. Pairs with readJson.
     *
     * @param value Any JSON-serializable value
     * @returns     JSON string
     */
    function writeJson(value) {
        return JSON.stringify(value);
    }

    /**
     * Read pageData as the new per-mode shape, migrating the legacy
     * `[[appId,...],...]` shape on the fly. Always returns an array of
     * `{autoFill, snap, free}` objects, never null.
     */
    function readPageData() {
        var raw = readJson(pageData, []);
        if (!Array.isArray(raw) || raw.length === 0) {
            return [{ autoFill: [], snap: [], free: [] }];
        }
        var out = [];
        for (var i = 0; i < raw.length; ++i) {
            var p = raw[i];
            if (Array.isArray(p)) {
                // Legacy: bare array of appIds → autoFill bag.
                out.push({ autoFill: p.slice(), snap: [], free: [] });
            } else if (p && typeof p === "object") {
                out.push({
                    autoFill: Array.isArray(p.autoFill) ? p.autoFill : [],
                    snap:     Array.isArray(p.snap)     ? p.snap     : [],
                    free:     Array.isArray(p.free)     ? p.free     : []
                });
            } else {
                out.push({ autoFill: [], snap: [], free: [] });
            }
        }
        return out;
    }
}

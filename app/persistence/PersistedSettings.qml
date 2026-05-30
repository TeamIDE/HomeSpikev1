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
        category: "homeSpike"
        // pageData is a JSON array of arrays of appIds, one inner array per page.
        property string pageData:     '[[]]'
        property int    pageCount:    1
        property string hiddenAppIds: "[]"
        property string dockOrder:    "[]"
        property bool   dockEnabled:  false
        // Height of the visible dock background plate, in grid units.
        // 1.0 ≈ a thin line under the icons; 12.0 wraps the icons fully.
        property real   dockBgHeight: 12.0
    }

    // ---- Read/write aliases so callers can bind to and mutate values
    //      without poking the underlying Settings object directly. ----
    property alias pageData:     store.pageData
    property alias pageCount:    store.pageCount
    property alias hiddenAppIds: store.hiddenAppIds
    property alias dockOrder:    store.dockOrder
    property alias dockEnabled:  store.dockEnabled
    property alias dockBgHeight: store.dockBgHeight

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
}

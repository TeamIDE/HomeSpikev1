/**
 * @file PageModelRegistry
 * @description Owns the runtime models that the UI binds against:
 *   N per-page ListModels (one per home screen) and one dock ListModel.
 *   Reconciles their contents against PersistedSettings + AppHarvester.
 *
 *   Every mutation routes through this module — there are no other writers
 *   of pageModels/dockApps. Persistence happens only via persistOrder(),
 *   which is invoked from explicit user actions (drag end, dock toggle,
 *   remove, page count change) — never from rebuildVisible().
 *
 *   Page count is fixed-pool (up to maxPages) to avoid dynamic ListModel
 *   creation, which has lifecycle headaches in QML. We just clear unused
 *   models when pageCount shrinks.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15

Item {
    id: root

    /** Injected by parent. Provides persist.pageData, pageCount, etc. */
    property var persist: null

    /** Injected by parent. Provides appHarvest.count + itemAt(i). */
    property var appHarvest: null

    /** Hard cap on swipeable pages. */
    readonly property int maxPages: 5

    /** Hard cap on dock entries. */
    readonly property int dockMax: 5

    /** Per-page models (fixed pool — only the first pageCount are used). */
    ListModel { id: page0 }
    ListModel { id: page1 }
    ListModel { id: page2 }
    ListModel { id: page3 }
    ListModel { id: page4 }
    readonly property var pageModels: [page0, page1, page2, page3, page4]

    /** Dock contents (only populated when persist.dockEnabled). */
    ListModel { id: _dock }
    readonly property var dockApps: _dock

    // --------------------------------------------------------------
    // Reconciliation: pull saved pageData → fill pageModels + dockApps
    // --------------------------------------------------------------

    /**
     * Read persisted state, populate the per-page models and dock from it,
     * skipping hidden apps and silently dropping uninstalled appIds. Any
     * newly-installed apps not yet placed get auto-appended to the last
     * page. Pure read — never writes back. (Writing during incremental
     * AppHarvester loads would destroy the saved layout.)
     */
    function rebuildVisible() {
        var pageData  = _normalisedPageData();
        var hiddenSet = _setFromArray(persist.readJson(persist.hiddenAppIds, []));
        var dockIds   = persist.dockEnabled ? persist.readJson(persist.dockOrder, []) : [];
        var dockSet   = _setFromArray(dockIds);
        var source    = _snapshotSource();

        _fillDock(dockIds, source, hiddenSet);
        _fillPages(pageData, source, hiddenSet, dockSet);
        _autoAppendNewApps(source, hiddenSet);
        _clearUnusedPages();
    }

    /**
     * Read persist.pageData and pad/truncate it to current pageCount.
     * When trimming, overflow pages merge into the last kept page.
     */
    function _normalisedPageData() {
        var pageData = persist.readJson(persist.pageData, [[]]);
        if (!Array.isArray(pageData) || pageData.length === 0) pageData = [[]];

        var pc = Math.min(Math.max(1, persist.pageCount), maxPages);
        while (pageData.length < pc) pageData.push([]);
        if (pageData.length > pc) {
            var overflow = [];
            for (var z = pc; z < pageData.length; ++z) overflow = overflow.concat(pageData[z]);
            pageData = pageData.slice(0, pc);
            pageData[pc - 1] = pageData[pc - 1].concat(overflow);
        }
        return pageData;
    }

    /**
     * Snapshot AppHarvester into a {appId: {appId,name,icon,_used?}} map +
     * an ordered list of appIds. Used to populate pages/dock without
     * iterating the Repeater repeatedly.
     */
    function _snapshotSource() {
        var source = {};
        var sourceIds = [];
        for (var j = 0; j < appHarvest.count; ++j) {
            var it = appHarvest.itemAt(j);
            if (!it || !it.appId) continue;
            source[it.appId] = { appId: it.appId, name: it.name, icon: it.icon };
            sourceIds.push(it.appId);
        }
        source._order = sourceIds;
        return source;
    }

    function _fillDock(dockIds, source, hiddenSet) {
        _dock.clear();
        for (var dx = 0; dx < dockIds.length && dx < dockMax; ++dx) {
            var did = dockIds[dx];
            if (hiddenSet[did])      continue;
            if (!source[did])        continue;
            if (source[did]._used)   continue;
            _dock.append(source[did]);
            source[did]._used = true;
        }
    }

    function _fillPages(pageData, source, hiddenSet, dockSet) {
        var pc = persist.pageCount;
        for (var p = 0; p < pc; ++p) {
            pageModels[p].clear();
            var ids = pageData[p] || [];
            for (var k = 0; k < ids.length; ++k) {
                var id = ids[k];
                if (hiddenSet[id])     continue;
                if (dockSet[id])       continue;
                if (!source[id])       continue;
                if (source[id]._used)  continue;
                pageModels[p].append(source[id]);
                source[id]._used = true;
            }
        }
    }

    function _autoAppendNewApps(source, hiddenSet) {
        var last = persist.pageCount - 1;
        var sourceIds = source._order || [];
        for (var m = 0; m < sourceIds.length; ++m) {
            var sid = sourceIds[m];
            if (source[sid]._used) continue;
            if (hiddenSet[sid])    continue;
            pageModels[last].append(source[sid]);
        }
    }

    function _clearUnusedPages() {
        for (var px = persist.pageCount; px < maxPages; ++px) pageModels[px].clear();
    }

    function _setFromArray(arr) {
        var set = {};
        for (var i = 0; i < arr.length; ++i) set[arr[i]] = true;
        return set;
    }

    // --------------------------------------------------------------
    // User-action handlers — every write to persist routes through here
    // --------------------------------------------------------------

    /**
     * Serialize the current pageModels + dockApps back to persist.
     * Call from explicit user actions only (drag end, etc.), never from
     * rebuildVisible — see the file header.
     */
    function persistOrder() {
        var pages = [];
        for (var p = 0; p < persist.pageCount; ++p) {
            var ids = [];
            for (var i = 0; i < pageModels[p].count; ++i) ids.push(pageModels[p].get(i).appId);
            pages.push(ids);
        }
        persist.pageData = persist.writeJson(pages);

        var dockIds = [];
        for (var j = 0; j < _dock.count; ++j) dockIds.push(_dock.get(j).appId);
        persist.dockOrder = persist.writeJson(dockIds);
    }

    /**
     * Mark an appId as hidden from HomeSpike. Stays installed; just no
     * longer appears on any page or in the _dock. Reverse via addAppsToHome.
     */
    function hideApp(appId) {
        var hidden = persist.readJson(persist.hiddenAppIds, []);
        if (hidden.indexOf(appId) === -1) {
            hidden.push(appId);
            persist.hiddenAppIds = persist.writeJson(hidden);
        }
        rebuildVisible();
    }

    /**
     * Enable or disable the _dock. Disabling moves any docked apps to the
     * end of the last page; enabling starts with an empty _dock.
     */
    function toggleDock(enabled) {
        if (enabled === persist.dockEnabled) return;
        if (!enabled) {
            var pages = persist.readJson(persist.pageData, [[]]);
            var dockIds = persist.readJson(persist.dockOrder, []);
            if (pages.length === 0) pages = [[]];
            for (var i = 0; i < dockIds.length; ++i) {
                if (pages[pages.length - 1].indexOf(dockIds[i]) === -1) {
                    pages[pages.length - 1].push(dockIds[i]);
                }
            }
            persist.pageData = persist.writeJson(pages);
            persist.dockOrder = "[]";
        }
        persist.dockEnabled = enabled;
        rebuildVisible();
    }

    /**
     * Change the number of home pages (clamped 1..maxPages). When reduced,
     * the trimmed pages' apps merge into the new last page.
     */
    function setPageCount(n) {
        n = Math.min(Math.max(1, n), maxPages);
        if (n === persist.pageCount) return;
        persist.pageCount = n;
        rebuildVisible();
    }

    /**
     * Append a batch of appIds to the last page as if the user had asked
     * to add each one. Un-hides any that were previously removed, skips
     * any already placed. Used by the cross-process inbox.
     */
    function addAppsToHome(appIds) {
        var placed = _indexPlacedApps();
        var hidden = persist.readJson(persist.hiddenAppIds, []);
        var hiddenSet = _setFromArray(hidden);

        var changed = false;
        for (var k = 0; k < appIds.length; ++k) {
            var appId = appIds[k];

            if (hiddenSet[appId]) {
                var idx = hidden.indexOf(appId);
                if (idx >= 0) hidden.splice(idx, 1);
                delete hiddenSet[appId];
                changed = true;
            }
            if (placed[appId]) continue;

            var src = _findSourceApp(appId);
            if (!src) continue;

            pageModels[persist.pageCount - 1].append(src);
            placed[appId] = true;
            changed = true;
        }

        if (changed) {
            persist.hiddenAppIds = persist.writeJson(hidden);
            persistOrder();
        }
    }

    function _indexPlacedApps() {
        var placed = {};
        for (var p = 0; p < persist.pageCount; ++p) {
            for (var ii = 0; ii < pageModels[p].count; ++ii) {
                placed[pageModels[p].get(ii).appId] = true;
            }
        }
        for (var dd = 0; dd < _dock.count; ++dd) {
            placed[_dock.get(dd).appId] = true;
        }
        return placed;
    }

    function _findSourceApp(appId) {
        for (var j = 0; j < appHarvest.count; ++j) {
            var it = appHarvest.itemAt(j);
            if (it && it.appId === appId) {
                return { appId: it.appId, name: it.name, icon: it.icon };
            }
        }
        return null;
    }
}

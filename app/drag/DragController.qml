/**
 * @file DragController
 * @description Owns every part of the drag-and-drop interaction: the
 *   live drag state, the floating icon visual, edge-flip-to-next-page
 *   timer, and the cell-targeting math. Mutates page/dock models
 *   directly via the injected PageModelRegistry.
 *
 *   Design rules:
 *   - moveDrag never crosses pages on its own. Cross-page transitions
 *     happen ONLY in edgeFlipTimer, which is the user's deliberate hover-
 *     near-edge gesture. This avoids the "stale currentPage" auto-jump
 *     bugs we fought during initial development.
 *   - startDrag's claimed (container, page, index) from the press delegate
 *     is treated as a hint. The authoritative source is _findAppLocation
 *     which scans the actual models — delegates can lie about their page
 *     index after model edits.
 *   - persistOrder fires only from endDrag, never from moveDrag (every
 *     model mutation along a drag would write to disk N times per second).
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: root

    // ---- Injected dependencies (set by parent) ----
    /** PageModelRegistry — owns pageModels[] + dockApps. */
    property var pages: null

    /** PersistedSettings — used for pageCount + dockEnabled reads. */
    property var persist: null

    /** Horizontal ListView of pages. Used for currentPage + edge-flip scrolling. */
    property var pagesView: null

    /** Dock Rectangle. Used as the geometry target for dock hit-testing. */
    property var dockBar: null

    /** Set true by moveDrag when the drag cursor is over the dock area
     *  AND the source isn't already in the dock. Caller binds dock
     *  highlighting to this. */
    property bool targetingDock: false

    // ---- Live drag state ----
    readonly property bool dragging: sourceIndex >= 0
    property int    sourceIndex: -1
    property int    sourcePage:  -1
    property string sourceContainer: ""
    property string sourceAppId: ""
    property string sourceName:  ""
    property string sourceIcon:  ""

    z: 300
    anchors.fill: parent

    // ============================================================
    // Edge-flip: after holding near the screen edge for 600ms, jump
    // to the adjacent page AND carry the dragged icon with us.
    // ============================================================
    Timer {
        id: edgeFlipTimer
        interval: 600
        property int direction: 0   // -1 left, +1 right

        onTriggered: {
            var target = pagesView.currentPage + direction;
            if (target < 0 || target >= persist.pageCount) return;

            if (_canCarryToPage(target)) _carryToPage(target);
            pagesView.positionViewAtIndex(target, ListView.Beginning);
        }
    }

    function _canCarryToPage(targetPage) {
        return root.dragging
            && sourceContainer === "grid"
            && sourcePage !== targetPage
            && sourcePage >= 0
            && sourceIndex >= 0
            && sourceIndex < pages.pageModels[sourcePage].count;
    }

    function _carryToPage(targetPage) {
        var item = {
            appId: sourceAppId,
            name:  sourceName,
            icon:  sourceIcon
        };
        pages.pageModels[sourcePage].remove(sourceIndex, 1);
        pages.pageModels[targetPage].append(item);
        sourcePage = targetPage;
        sourceIndex = pages.pageModels[targetPage].count - 1;
    }

    // ============================================================
    // Public API: called from TileBody MouseArea handlers
    // ============================================================

    /**
     * Begin a drag. (container, page, idx) are hints from the press delegate;
     * the real source is whichever model actually has appId. Bail silently
     * if appId can't be located.
     */
    function startDrag(container, page, idx, appId, name, icon, x, y) {
        var loc = _findAppLocation(appId);
        if (!loc) {
            sourceContainer = "";
            sourcePage = -1;
            sourceIndex = -1;
            return;
        }
        sourceContainer = loc.container;
        sourcePage = loc.page;
        sourceIndex = loc.index;
        sourceAppId = appId;
        sourceName = name;
        sourceIcon = icon;
        floatingIcon.x = x - floatingIcon.width / 2;
        floatingIcon.y = y - floatingIcon.height / 2;
    }

    /**
     * Update the drag position. Reorders within the source page or
     * transitions in/out of the dock as appropriate. Never crosses pages —
     * that's edgeFlipTimer's job.
     */
    function moveDrag(x, y) {
        if (!dragging || sourceContainer === "") return;
        if (!_relocateSource()) return;

        floatingIcon.x = x - floatingIcon.width / 2;
        floatingIcon.y = y - floatingIcon.height / 2;

        _updateEdgeFlipDirection(x);

        if (_isOverDock(x, y)) _handleOverDock(x, y);
        else _handleOverGrid(x, y);
    }

    /**
     * Finalise the drag. Persist any reordering that happened, clear state.
     */
    function endDrag() {
        edgeFlipTimer.stop();
        edgeFlipTimer.direction = 0;
        targetingDock = false;
        if (sourceIndex >= 0) pages.persistOrder();
        sourceIndex = -1;
        sourcePage  = -1;
        sourceContainer = "";
    }

    /**
     * Discard any in-flight drag state WITHOUT persisting. Use for defensive
     * cleanup when a previous drag's onReleased never fired (e.g. its
     * delegate was destroyed mid-drag during a cross-page scroll).
     */
    function abort() {
        edgeFlipTimer.stop();
        edgeFlipTimer.direction = 0;
        targetingDock = false;
        sourceIndex = -1;
        sourcePage  = -1;
        sourceContainer = "";
        sourceAppId = "";
    }

    // ============================================================
    // moveDrag helpers
    // ============================================================

    /**
     * Re-find the source's index by appId. Index can shift between moveDrag
     * calls because other drags may have reordered the models. Returns true
     * on success, false (after calling endDrag) if the source vanished.
     */
    function _relocateSource() {
        var foundIdx = -1;
        if (sourceContainer === "grid") {
            if (sourcePage < 0 || sourcePage >= persist.pageCount) return false;
            var m = pages.pageModels[sourcePage];
            for (var i = 0; i < m.count; ++i) {
                if (m.get(i).appId === sourceAppId) { foundIdx = i; break; }
            }
        } else if (sourceContainer === "dock") {
            for (var j = 0; j < pages.dockApps.count; ++j) {
                if (pages.dockApps.get(j).appId === sourceAppId) { foundIdx = j; break; }
            }
        }
        if (foundIdx < 0) {
            endDrag();
            return false;
        }
        sourceIndex = foundIdx;
        return true;
    }

    function _updateEdgeFlipDirection(x) {
        var edgeMargin = units.gu(3);
        var newDir = 0;
        if (x < edgeMargin) newDir = -1;
        else if (x > width - edgeMargin) newDir = +1;
        if (newDir !== edgeFlipTimer.direction) {
            edgeFlipTimer.stop();
            edgeFlipTimer.direction = newDir;
            if (newDir !== 0) edgeFlipTimer.start();
        }
    }

    function _isOverDock(x, y) {
        if (!persist.dockEnabled || !dockBar) return false;
        var dp = root.mapToItem(dockBar, x, y);
        return dp.x >= 0 && dp.x <= dockBar.width && dp.y >= 0 && dp.y <= dockBar.height;
    }

    function _handleOverDock(x, y) {
        targetingDock = sourceContainer !== "dock";
        var dp = root.mapToItem(dockBar, x, y);

        if (sourceContainer === "dock") {
            _reorderInDock(dp.x);
        } else if (sourceContainer === "grid") {
            _moveGridToDock();
        }
    }

    function _reorderInDock(dockX) {
        var dockCellW = units.gu(10);
        var targetIdx = Math.floor(dockX / dockCellW);
        if (targetIdx < 0) targetIdx = 0;
        if (targetIdx >= pages.dockApps.count) targetIdx = pages.dockApps.count - 1;
        if (targetIdx !== sourceIndex) {
            pages.dockApps.move(sourceIndex, targetIdx, 1);
            sourceIndex = targetIdx;
        }
    }

    function _moveGridToDock() {
        if (pages.dockApps.count >= pages.dockMax) return;
        pages.pageModels[sourcePage].remove(sourceIndex, 1);
        pages.dockApps.append({
            appId: sourceAppId,
            name:  sourceName,
            icon:  sourceIcon
        });
        sourceContainer = "dock";
        sourcePage = -1;
        sourceIndex = pages.dockApps.count - 1;
    }

    function _handleOverGrid(x, y) {
        targetingDock = false;
        var target = _computeGridTarget(x, y);
        if (target < 0) return;

        if (sourceContainer === "dock") {
            _moveDockToGrid();
        } else if (sourceContainer === "grid") {
            _reorderInPage(target);
        }
    }

    /**
     * Convert a Window-space (x,y) into a target cell index on the current
     * page. Accounts for the GridView's left/right anchor margins.
     * Returns -1 if the point is above the grid area.
     */
    function _computeGridTarget(x, y) {
        var leftMargin = units.gu(1);
        var topMargin  = units.gu(5);            // pagesView.topMargin
        var gridWidth  = pagesView.width - 2 * leftMargin;
        var cellH      = units.gu(11);
        var cols       = 4;
        var cellW      = gridWidth / cols;

        var pageX = x - leftMargin;
        var pageY = y - topMargin;
        if (pageY < 0) return -1;
        if (pageX < 0) pageX = 0;
        if (pageX >= gridWidth) pageX = gridWidth - 1;

        var col = Math.floor(pageX / cellW);
        var row = Math.floor(pageY / cellH);
        if (col < 0) col = 0;
        if (col >= cols) col = cols - 1;
        return row * cols + col;
    }

    function _moveDockToGrid() {
        var dropPage = pagesView.currentPage;
        if (dropPage < 0 || dropPage >= persist.pageCount) return;
        var item = { appId: sourceAppId, name: sourceName, icon: sourceIcon };
        pages.dockApps.remove(sourceIndex, 1);
        pages.pageModels[dropPage].append(item);
        sourceContainer = "grid";
        sourcePage = dropPage;
        sourceIndex = pages.pageModels[dropPage].count - 1;
    }

    function _reorderInPage(target) {
        var pageModel = pages.pageModels[sourcePage];
        if (target < 0) target = 0;
        if (target >= pageModel.count) target = pageModel.count - 1;
        if (target !== sourceIndex) {
            pageModel.move(sourceIndex, target, 1);
            sourceIndex = target;
        }
    }

    // ============================================================
    // Authoritative source lookup — used by startDrag
    // ============================================================

    /**
     * Find which model (and at what index) actually contains appId.
     * Returns {container, page, index} or null.
     */
    function _findAppLocation(appId) {
        for (var p = 0; p < persist.pageCount; ++p) {
            var m = pages.pageModels[p];
            for (var i = 0; i < m.count; ++i) {
                if (m.get(i).appId === appId) return { container: "grid", page: p, index: i };
            }
        }
        for (var d = 0; d < pages.dockApps.count; ++d) {
            if (pages.dockApps.get(d).appId === appId) {
                return { container: "dock", page: -1, index: d };
            }
        }
        return null;
    }

    // ============================================================
    // Visual: the floating icon that tracks the drag cursor
    // ============================================================
    LomiriShape {
        id: floatingIcon
        visible: root.dragging
        width: units.gu(6) * 1.15
        height: 7.5 / 8 * width
        radius: "medium"
        borderSource: "undefined"
        sourceFillMode: LomiriShape.PreserveAspectCrop
        opacity: 0.92
        source: Image {
            asynchronous: true
            sourceSize.width: floatingIcon.width
            source: root.sourceIcon
        }
    }
}

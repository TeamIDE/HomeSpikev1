/**
 * @file main
 * @description HomeSpike composition root. Wires every module together —
 *   persistence, wallpaper, app source, page/dock models, drag controller,
 *   cross-process inbox, tiles, overlays, and edit-mode chrome — and
 *   defines the visual stack (wallpaper → pages → page dots → dock →
 *   chrome → overlays).
 *
 *   Each module lives in its own subdir under app/ and is responsible for
 *   one slice of behaviour. main.qml owns nothing — every line here is
 *   either a module instantiation or a binding between modules.
 *
 * @status Stable.
 * @issues None
 * @todo
 *   - [ ] Extract the inline pagesView ListView + page-dots Row into
 *         a PagesView module once the design settles (currently fine
 *         since it's the canvas everything else binds to).
 */
import QtQuick 2.15
import Lomiri.Components 1.3
import "persistence"
import "wallpaper"
import "inbox"
import "models"
import "drag"
import "tiles"
import "chrome"
import "overlays"

// HomeSpike root is now an Item, not a Window — loaded inline by Lomiri's
// Stage.qml as the background layer (z=-2). HomeSpike no longer runs as a
// separate process; it lives inside the lomiri shell process.
Item {
    id: root
    anchors.fill: parent

    // Solid background under everything (the WallpaperResolver Image draws
    // over this; the colour shows for the brief moment before it loads).
    Rectangle { anchors.fill: parent; color: "#1d2540" }

    // ============================================================
    // State
    // ============================================================
    property bool editMode: false
    readonly property real dockHeight: units.gu(12)

    // Lomiri's Stage.qml writes the launcher's current visible width here
    // (via the Loader's binding) so we can inset our grid/dock/dots and
    // not let the launcher panel cover the leftmost icon column.
    property real leftReserve: 0

    // Exposed for Lomiri's Shell.qml to read — when true, the left launcher
    // panel is force-collapsed (lockedVisible=false) so the dock owns the
    // bottom row of launcher icons and the grid uses the full width.
    readonly property bool dockEnabled: persist.dockEnabled

    /** Fired when the user taps any tile (grid or dock) to launch its app.
     *  Stage.qml's wallpaper Loader Connections listens for this and drops
     *  homeShown immediately — without it, Mir's focus-echo can be
     *  misread as the launch and the home overlay stays stuck on top. */
    signal launchRequested(string appId)

    // ---- Core modules ----
    PersistedSettings { id: persist }
    WallpaperResolver { id: wallpaper }
    AppHarvester      { id: appHarvest }

    PageModelRegistry {
        id: pages
        persist: persist
        appHarvest: appHarvest
    }

    Component.onCompleted: {
        pages.rebuildVisible();
        pendingAdds.pollNow();
    }
    Connections {
        target: appHarvest
        function onCountChanged() { pages.rebuildVisible() }
    }

    // ============================================================
    // Cross-process inbox: the patched Lomiri Drawer.qml appends appIds
    // to this file on long-press; the inbox watcher emits linesReceived
    // and we place each new appId on the home grid.
    // ============================================================
    PendingAddsInbox {
        id: pendingAdds
        filePath: "/home/phablet/.config/home-spike/pending-adds.txt"
        onLinesReceived: (appIds) => pages.addAppsToHome(appIds)
    }


    // TileBody now lives in tiles/TileBody.qml — instantiated as
    // a Component below where the per-page and per-dock delegates live.

    // ============================================================
    // Visual stack
    // ============================================================
    Image {
        anchors.fill: parent
        source: wallpaper.uri
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
    }
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.4 }

    // ----- Horizontal pages ListView -----
    ListView {
        id: pagesView
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            bottom: pageDots.top
            topMargin: units.gu(5)
            bottomMargin: units.gu(1)
            leftMargin: root.leftReserve
        }
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        boundsBehavior: Flickable.StopAtBounds
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 250
        interactive: !dragController.dragging
        clip: true
        model: persist.pageCount

        // Index of currently centered page (for indicators + drag drop target)
        property int currentPage: Math.round(contentX / Math.max(1, width))

        // Shared grid geometry — used for autoFill + snap rendering AND
        // by DragController to translate a drop point into (col,row).
        readonly property real gridLeftMargin: units.gu(1)
        readonly property real gridRightMargin: units.gu(1)
        readonly property real cellH: units.gu(11)
        readonly property real tileW: units.gu(9)
        readonly property real tileH: units.gu(11)

        delegate: Item {
            id: pageDelegate
            width: pagesView.width
            height: pagesView.height
            property int pageIndex: index
            readonly property real cellW: (width - pagesView.gridLeftMargin - pagesView.gridRightMargin) / pages.cols

            // One Repeater drives all three placement modes — only the
            // x/y bindings differ based on persist.placementMode.
            Repeater {
                id: tileRepeater
                model: pages.pageModels[pageDelegate.pageIndex]
                delegate: Item {
                    id: tileWrap
                    width: pagesView.tileW
                    height: pagesView.tileH

                    // Read positional roles ourselves so the binding can
                    // switch source field when placementMode changes.
                    readonly property string mode: persist.placementMode
                    x: {
                        if (mode === "autoFill") {
                            return pagesView.gridLeftMargin
                                 + (index % pages.cols) * pageDelegate.cellW
                                 + (pageDelegate.cellW - width) / 2;
                        }
                        if (mode === "snap") {
                            var c = model.col >= 0 ? model.col : 0;
                            return pagesView.gridLeftMargin
                                 + c * pageDelegate.cellW
                                 + (pageDelegate.cellW - width) / 2;
                        }
                        // free — values <= 0.001 are treated as "unset"
                        // (covers both the -0.5 sentinel and stale rows
                        // truncated to 0 by older builds' int-typed roles).
                        var f = (model.xFrac > 0.001) ? model.xFrac : 0.5;
                        return f * pageDelegate.width - width / 2;
                    }
                    y: {
                        if (mode === "autoFill") {
                            return Math.floor(index / pages.cols) * pagesView.cellH;
                        }
                        if (mode === "snap") {
                            var r = model.row >= 0 ? model.row : 0;
                            return r * pagesView.cellH;
                        }
                        // free — see x binding for the > 0.001 reasoning.
                        var f = (model.yFrac > 0.001) ? model.yFrac : 0.5;
                        return f * pageDelegate.height - height / 2;
                    }
                    // Smooth re-flow when models reorder or modes change.
                    // Disabled while THIS tile is being dragged so it
                    // doesn't fight the floating-icon visual.
                    Behavior on x {
                        enabled: !(dragController.dragging
                                   && dragController.sourceContainer === "grid"
                                   && dragController.sourcePage === pageDelegate.pageIndex
                                   && dragController.sourceIndex === index)
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        enabled: !(dragController.dragging
                                   && dragController.sourceContainer === "grid"
                                   && dragController.sourcePage === pageDelegate.pageIndex
                                   && dragController.sourceIndex === index)
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    opacity: (dragController.dragging
                              && dragController.sourceContainer === "grid"
                              && dragController.sourcePage === pageDelegate.pageIndex
                              && dragController.sourceIndex === index) ? 0.0 : 1.0

                    TileBody {
                        anchors.fill: parent
                        appId: model.appId
                        appName: model.name
                        iconSrc: model.icon
                        container: "grid"
                        sourcePage: pageDelegate.pageIndex
                        indexInModel: index
                        editMode: root.editMode
                        controller: dragController
                        onRemoveRequested: (id, name) => confirmRemove.show(id, name)
                        onEditModeRequested: root.editMode = true
                        onLaunchRequested: (id) => root.launchRequested(id)
                    }
                }
            }
        }
    }

    // ----- Page indicator dots -----
    Row {
        id: pageDots
        anchors {
            horizontalCenter: parent.horizontalCenter
            // Keep the dots optically centered in the content area (the area
            // to the right of the launcher panel) by shifting them by half
            // the reserved left margin.
            horizontalCenterOffset: root.leftReserve / 2
            bottom: persist.dockEnabled ? dockBar.top : parent.bottom
            bottomMargin: units.gu(1.5)
        }
        spacing: units.gu(1)
        visible: persist.pageCount > 1
        Repeater {
            model: persist.pageCount
            delegate: Rectangle {
                width: units.gu(0.8); height: width
                radius: width / 2
                color: pagesView.currentPage === index ? "white" : "#88ffffff"
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    // ----- Dock zone (always full icon-height for hit-testing) -----
    Item {
        id: dockBar
        visible: persist.dockEnabled
        anchors {
            bottom: parent.bottom; left: parent.left; right: parent.right
            // Smaller bottom margin sits the dock closer to the screen edge,
            // matching the iOS-style "icons near the bottom" feel.
            bottomMargin: units.gu(0.25); leftMargin: root.leftReserve + units.gu(2); rightMargin: units.gu(2)
        }
        height: root.dockHeight

        // Visible background plate — resizable via Settings → "Dock background height".
        // Vertically centered in the zone; icons can extend above/below if it's thin.
        Rectangle {
            id: dockBg
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: units.gu(persist.dockBgHeight)
            radius: Math.min(units.gu(2.5), height / 2)
            color: dragController.targetingDock ? "#55ffffff" : "#33ffffff"
            border.color: dragController.targetingDock ? "white" : "transparent"
            border.width: 1
            Behavior on color  { ColorAnimation  { duration: 120 } }
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Row {
            anchors.centerIn: parent
            spacing: units.gu(1)
            Repeater {
                model: pages.dockApps
                delegate: Item {
                    width: units.gu(9)
                    height: root.dockHeight - units.gu(2)
                    opacity: (dragController.dragging
                              && dragController.sourceContainer === "dock"
                              && dragController.sourceIndex === index) ? 0.0 : 1.0

                    TileBody {
                        anchors.fill: parent
                        appId: model.appId
                        appName: model.name
                        iconSrc: model.icon
                        container: "dock"
                        indexInModel: index
                        editMode: root.editMode
                        controller: dragController
                        onRemoveRequested: (id, name) => confirmRemove.show(id, name)
                        onEditModeRequested: root.editMode = true
                        onLaunchRequested: (id) => root.launchRequested(id)
                    }
                }
            }
        }
    }

    // ============================================================
    // Edit-mode chrome
    // ============================================================
    EditModeDonePill {
        active: root.editMode
        anchors {
            top: parent.top; right: parent.right
            topMargin: units.gu(4); rightMargin: units.gu(2)
        }
        onDismissed: root.editMode = false
    }

    SettingsGearButton {
        active: root.editMode
        bottomOffset: persist.dockEnabled ? root.dockHeight + units.gu(2.5) : units.gu(4)
        anchors {
            bottom: parent.bottom; right: parent.right
            bottomMargin: bottomOffset
            rightMargin: units.gu(2)
        }
        onTriggered: settingsOverlay.visible = true
    }

    // ============================================================
    // Drag controller — owns all drag-and-drop state + visual
    // ============================================================
    DragController {
        id: dragController
        pages: pages
        persist: persist
        pagesView: pagesView
        dockBar: dockBar
    }

    // ============================================================
    // Settings + confirm-remove overlays
    // ============================================================
    SettingsOverlay {
        id: settingsOverlay
        pageCount: persist.pageCount
        maxPages: pages.maxPages
        dockEnabled: persist.dockEnabled
        dockBgHeight: persist.dockBgHeight
        placementMode: persist.placementMode
        leftReserve: root.leftReserve
        onPageCountAdjusted: (n) => pages.setPageCount(n)
        onDockToggled: (on) => pages.toggleDock(on)
        onDockBgHeightAdjusted: (gu) => persist.dockBgHeight = gu
        // PageModelRegistry's Connections watcher catches the persist
        // change and re-renders from the new mode's saved slot.
        onPlacementModeAdjusted: (mode) => persist.placementMode = mode
    }

    ConfirmRemoveOverlay {
        id: confirmRemove
        leftReserve: root.leftReserve
        onConfirmed: (appId) => pages.hideApp(appId)
    }
}

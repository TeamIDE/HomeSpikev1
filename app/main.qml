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
import QtQuick.Window 2.15
import Lomiri.Components 1.3
import "persistence"
import "wallpaper"
import "inbox"
import "models"
import "drag"
import "tiles"
import "chrome"
import "overlays"

Window {
    id: root
    visible: true
    visibility: Window.Maximized
    color: "#1d2540"
    title: "Home Spike"

    // ============================================================
    // State
    // ============================================================
    property bool editMode: false
    readonly property real dockHeight: units.gu(12)

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

        delegate: Item {
            width: pagesView.width
            height: pagesView.height
            property int pageIndex: index

            GridView {
                anchors {
                    fill: parent
                    leftMargin: units.gu(1); rightMargin: units.gu(1)
                }
                cellWidth: width / 4
                cellHeight: units.gu(11)
                model: pages.pageModels[pageIndex]
                interactive: !dragController.dragging
                clip: true

                move:          Transition { NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic } }
                moveDisplaced: Transition { NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic } }

                delegate: Item {
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight
                    opacity: (dragController.dragging
                              && dragController.sourceContainer === "grid"
                              && dragController.sourcePage === pageIndex
                              && dragController.sourceIndex === index) ? 0.0 : 1.0

                    TileBody {
                        anchors.fill: parent
                        appId: model.appId
                        appName: model.name
                        iconSrc: model.icon
                        container: "grid"
                        sourcePage: pageIndex
                        indexInModel: index
                        editMode: root.editMode
                        controller: dragController
                        onRemoveRequested: (id, name) => confirmRemove.show(id, name)
                        onEditModeRequested: root.editMode = true
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
            bottomMargin: units.gu(0.25); leftMargin: units.gu(2); rightMargin: units.gu(2)
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
        onPageCountAdjusted: (n) => pages.setPageCount(n)
        onDockToggled: (on) => pages.toggleDock(on)
        onDockBgHeightAdjusted: (gu) => persist.dockBgHeight = gu
    }

    ConfirmRemoveOverlay {
        id: confirmRemove
        onConfirmed: (appId) => pages.hideApp(appId)
    }
}

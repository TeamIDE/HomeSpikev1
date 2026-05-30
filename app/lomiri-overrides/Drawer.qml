/**
 * @file Drawer
 * @description HomeSpike's modified copy of Lomiri's drawer. Replaces the
 *   original delegate's `onPressAndHold` (which used to open an OpenStore
 *   link) with an in-scene context menu offering "Add to HomeSpike". The
 *   action writes the appId to a file inbox that the running HomeSpike
 *   polls and processes.
 *
 *   Original Lomiri file: /usr/share/lomiri/Launcher/Drawer.qml
 *   Installed by HomeSpike's install.sh; original preserved as .orig.
 *
 * @status Stable.
 * @issues OTA-fragile: a Lomiri upstream update overwrites our copy.
 *   install.sh re-applies on demand.
 * @todo None
 */
/*
 * Copyright (C) 2016 Canonical Ltd.
 * Copyright (C) 2020-2021 UBports Foundation
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.15
import Lomiri.Components 1.3
import Lomiri.Launcher 0.1
import Utils 0.1
import "../Components"
import Qt.labs.settings 1.0
import GSettings  1.0
import AccountsService 0.1
import QtGraphicalEffects 1.0

FocusScope {
    id: root

    property int panelWidth: 0
    readonly property bool moving: (appList && appList.moving) ? true : false
    readonly property Item searchTextField: searchField
    readonly property real delegateWidth: units.gu(10)
    property url background
    visible: x > -width
    property var fullyOpen: x === 0
    property var fullyClosed: x === -width
    property bool lightMode : false
    signal applicationSelected(string appId)

    // Request that the Drawer is opened fully, if it was partially closed then
    // brought back
    signal openRequested()

    // Request that the Drawer (and maybe its parent) is hidden, normally if
    // the Drawer has been dragged away.
    signal hideRequested()

    property bool allowSlidingAnimation: false
    property bool draggingHorizontally: false
    property int dragDistance: 0

    property var hadFocus: false
    property var oldSelectionStart: null
    property var oldSelectionEnd: null

    anchors {
        onRightMarginChanged: refocusInputAfterUserLetsGo()
    }

    Behavior on anchors.rightMargin {
        enabled: allowSlidingAnimation && !draggingHorizontally
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    onDraggingHorizontallyChanged: {
        // See refocusInputAfterUserLetsGo()
        if (draggingHorizontally) {
            hadFocus = searchField.focus;
            oldSelectionStart = searchField.selectionStart;
            oldSelectionEnd = searchField.selectionEnd;
            searchField.focus = false;
        } else {
            if (x < -units.gu(10)) {
                hideRequested();
            } else {
                openRequested();
            }
            refocusInputAfterUserLetsGo();
        }
    }

    Keys.onEscapePressed: {
        root.hideRequested()
    }

    onDragDistanceChanged: {
        anchors.rightMargin = Math.max(-drawer.width, anchors.rightMargin + dragDistance);
    }

    function resetOldFocus() {
        hadFocus = false;
        oldSelectionStart = null;
        oldSelectionEnd = null;
    }

    function refocusInputAfterUserLetsGo() {
        if (!draggingHorizontally) {
            if (fullyOpen && hadFocus) {
                searchField.focus = hadFocus;
                searchField.select(oldSelectionStart, oldSelectionEnd);
            } else if (fullyOpen || fullyClosed) {
                resetOldFocus();
            }

            if (fullyClosed) {
                searchField.text = "";
                appList.currentIndex = 0;
                searchField.focus = false;
                appList.focus = false;
            }
        }
    }

    function focusInput() {
        searchField.selectAll();
        searchField.focus = true;
    }

    function unFocusInput() {
        searchField.focus = false;
    }

    Keys.onPressed: {
        if (event.text.trim() !== "") {
            focusInput();
            searchField.text = event.text;
        }
        switch (event.key) {
            case Qt.Key_Right:
            case Qt.Key_Left:
            case Qt.Key_Down:
                appList.focus = true;
                break;
            case Qt.Key_Up:
                focusInput();
                break;
        }
        // Catch all presses here in case the navigation lets something through
        // We never want to end up in the launcher with focus
        event.accepted = true;
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onWheel: wheel.accepted = true
    }

    Rectangle {
        anchors.fill: parent
        color: root.lightMode ? "#CAFEFEFE" : "#BF000000"

        MouseArea {
            id: drawerHandle
            objectName: "drawerHandle"
            anchors {
                right: parent.right
                top: parent.top
                bottom: parent.bottom
            }
            width: units.gu(2)
            property int oldX: 0

            onPressed: {
                handle.active = true;
                oldX = mouseX;
            }
            onMouseXChanged: {
                var diff = oldX - mouseX;
                root.draggingHorizontally |= diff > units.gu(2);
                if (!root.draggingHorizontally) {
                    return;
                }
                root.dragDistance += diff;
                oldX = mouseX
            }
            onReleased: reset()
            onCanceled: reset()

            function reset() {
                root.draggingHorizontally = false;
                handle.active = false;
                root.dragDistance = 0;
            }

            Handle {
                id: handle
                anchors.fill: parent
                active: parent.pressed
            }
        }

        AppDrawerModel {
            id: appDrawerModel
        }

        AppDrawerProxyModel {
            id: sortProxyModel
            source: appDrawerModel
            filterString: searchField.displayText
            sortBy: AppDrawerProxyModel.SortByAToZ
        }

        Connections {
            target: i18n
            function onLanguageChanged() { appDrawerModel.refresh() }
        }

        Item {
            id: contentContainer
            anchors {
                left: parent.left
                right: drawerHandle.left
                top: parent.top
                bottom: parent.bottom
                leftMargin: root.panelWidth
            }

            Item {
                id: searchFieldContainer
                height: units.gu(4)
                anchors { left: parent.left; top: parent.top; right: parent.right; margins: units.gu(1) }

                TextField {
                    id: searchField
                    objectName: "searchField"
                    inputMethodHints: Qt.ImhNoPredictiveText; //workaround to get the clear button enabled without the need of a space char event or change in focus
                    anchors {
                        left: parent.left
                        top: parent.top
                        right: parent.right
                        bottom: parent.bottom
                    }
                    placeholderText: i18n.tr("Search…")
                    z: 100

                    KeyNavigation.down: appList

                    onAccepted: {
                        if (searchField.displayText != "" && appList) {
                            // In case there is no currentItem (it might have been filtered away) lets reset it to the first item
                            if (!appList.currentItem) {
                                appList.currentIndex = 0;
                            }
                            root.applicationSelected(appList.getFirstAppId());
                        }
                    }
                }
            }

            DrawerGridView {
                id: appList
                objectName: "drawerAppList"
                anchors {
                    left: parent.left
                    right: parent.right
                    top: searchFieldContainer.bottom
                    bottom: parent.bottom
                }
                height: rows * delegateHeight
                clip: true

                model: sortProxyModel
                delegateWidth: root.delegateWidth
                delegateHeight: units.gu(11)
                delegate: drawerDelegateComponent
                onDraggingVerticallyChanged: {
                    if (draggingVertically) {
                        unFocusInput();
                    }
                }

                refreshing: appDrawerModel.refreshing
                onRefresh: {
                    appDrawerModel.refresh();
                }
            }
        }

        Component {
            id: drawerDelegateComponent
            AbstractButton {
                id: drawerDelegate
                width: GridView.view.cellWidth
                height: units.gu(11)
                objectName: "drawerItem_" + model.appId

                readonly property bool focused: index === GridView.view.currentIndex && GridView.view.activeFocus

                onClicked: root.applicationSelected(model.appId)
                onPressAndHold: {
                  // HomeSpike integration: show in-scene context menu near the icon.
                  // AbstractButton doesn't expose mouseX/Y, so anchor to delegate center.
                  var pt = drawerDelegate.mapToItem(root, drawerDelegate.width / 2, drawerDelegate.height / 2);
                  homeSpikeMenu.anchorX = pt.x;
                  homeSpikeMenu.anchorY = pt.y;
                  homeSpikeMenu.appId = model.appId;
                  homeSpikeMenu.appName = model.name;
                  homeSpikeMenu.visible = true;
                }
                z: loader.active ? 1 : 0

                Column {
                    width: units.gu(9)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: childrenRect.height
                    spacing: units.gu(1)

                    LomiriShape {
                        id: appIcon
                        width: units.gu(6)
                        height: 7.5 / 8 * width
                        anchors.horizontalCenter: parent.horizontalCenter
                        radius: "medium"
                        borderSource: 'undefined'
                        source: Image {
                            id: sourceImage
                            asynchronous: true
                            sourceSize.width: appIcon.width
                            source: model.icon
                        }
                        sourceFillMode: LomiriShape.PreserveAspectCrop

                        StyledItem {
                            styleName: "FocusShape"
                            anchors.fill: parent
                            StyleHints {
                                visible: drawerDelegate.focused
                                radius: units.gu(2.55)
                            }
                        }
                    }

                    Label {
                        id: label
                        text: model.name
                        width: parent.width
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        fontSize: "small"
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight

                        Loader {
                            id: loader
                            x: {
                                var aux = 0;
                                if (item) {
                                    aux = label.width / 2 - item.width / 2;
                                    var containerXMap = mapToItem(contentContainer, aux, 0).x
                                    if (containerXMap < 0) {
                                        aux = aux - containerXMap;
                                        containerXMap = 0;
                                    }
                                    if (containerXMap + item.width > contentContainer.width) {
                                        aux = aux - (containerXMap + item.width - contentContainer.width);
                                    }
                                }
                                return aux;
                            }
                            y: -units.gu(0.5)
                            active: label.truncated && (drawerDelegate.hovered || drawerDelegate.focused)
                            sourceComponent: Rectangle {
                                color: root.lightMode ? LomiriColors.porcelain : LomiriColors.jet
                                width: fullLabel.contentWidth + units.gu(1)
                                height: fullLabel.height + units.gu(1)
                                radius: units.dp(4)
                                Label {
                                    id: fullLabel
                                    width: Math.min(root.delegateWidth * 2, implicitWidth)
                                    wrapMode: Text.Wrap
                                    horizontalAlignment: Text.AlignHCenter
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    anchors.centerIn: parent
                                    text: model.name
                                    fontSize: "small"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ============================================================
    // HomeSpike context menu — in-scene Rectangle (not PopupUtils),
    // so vol-key screenshots capture it and there's no Wayland-popup
    // z-order weirdness.
    // ============================================================
    MouseArea {
        anchors.fill: parent
        z: 999
        visible: homeSpikeMenu.visible
        onClicked: homeSpikeMenu.visible = false
    }

    Rectangle {
        id: homeSpikeMenu
        visible: false
        z: 1000
        radius: units.gu(0.5)
        color: "#1d2333"
        border.color: "#3a4262"
        border.width: 1

        property string appId: ""
        property string appName: ""
        property real anchorX: 0
        property real anchorY: 0

        // Sized to content — context-menu style, not a centered dialog.
        width: menuCol.implicitWidth
        height: menuCol.implicitHeight

        // Position just above the press point, clamped within screen bounds.
        x: Math.max(units.gu(1), Math.min(parent.width - width - units.gu(1), anchorX - width / 2))
        y: Math.max(units.gu(1), anchorY - height - units.gu(1))

        Column {
            id: menuCol
            // No outer padding — rows fill the menu edge-to-edge.

            // ---- Action rows. Add more here in the future. ----
            Rectangle {
                width: addRowLabel.implicitWidth + addRowIcon.width + units.gu(4)
                height: units.gu(4.5)
                color: addRowMouse.pressed ? "#3d5af1" : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: units.gu(1.5)
                    spacing: units.gu(1)
                    Text {
                        id: addRowIcon
                        anchors.verticalCenter: parent.verticalCenter
                        text: "+"
                        color: "white"
                        font.pixelSize: units.gu(2.2)
                        font.bold: true
                    }
                    Label {
                        id: addRowLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Add to HomeSpike"
                        color: "white"
                        fontSize: "small"
                    }
                }

                MouseArea {
                    id: addRowMouse
                    anchors.fill: parent
                    onClicked: {
                        var path = "/home/phablet/.config/home-spike/pending-adds.txt";
                        var existing = "";
                        var xhrR = new XMLHttpRequest();
                        xhrR.open("GET", "file://" + path, false);
                        try {
                            xhrR.send();
                            existing = xhrR.responseText || "";
                        } catch (e) {
                            // File may not exist yet (HomeSpike never started).
                            // Treat as empty inbox; the PUT below will create it.
                        }
                        var xhrW = new XMLHttpRequest();
                        xhrW.open("PUT", "file://" + path, false);
                        try {
                            xhrW.send(existing + homeSpikeMenu.appId + "\n");
                        } catch (e) {
                            console.error("HomeSpike: failed to write " + path + " — " + e);
                        }
                        homeSpikeMenu.visible = false;
                    }
                }
            }
        }
    }
}

/**
 * @file ConfirmRemoveOverlay
 * @description Full-screen modal that asks the user to confirm removing
 *   an app from the HomeSpike home grid. Self-contained Rectangle scrim
 *   + centered card (no PopupUtils — vol-key screenshots capture it and
 *   z-ordering with the GridView Just Works). Tap outside the card or
 *   the Cancel button to dismiss. Tap Remove → emits confirmed(appId).
 *
 *   "Remove" here means hide from HomeSpike, not uninstall the app.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Rectangle {
    id: root

    /** appId of the app the user is being asked about. */
    property string appId: ""

    /** Human-readable name shown in the prompt. */
    property string appName: ""

    /** Emitted when the user taps Remove. */
    signal confirmed(string appId)

    anchors.fill: parent
    z: 1000
    visible: false
    color: "#aa000000"

    /**
     * Show the overlay with a specific app's identity.
     */
    function show(targetAppId, targetAppName) {
        appId = targetAppId;
        appName = targetAppName;
        visible = true;
    }

    // Tap outside the card dismisses
    MouseArea {
        anchors.fill: parent
        onClicked: root.visible = false
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.85, units.gu(50))
        height: cardCol.height + units.gu(4)
        radius: units.gu(2)
        color: "#262d4d"

        // Swallow taps on the card itself so they don't bubble to the
        // dismiss MouseArea behind it.
        MouseArea { anchors.fill: parent }

        Column {
            id: cardCol
            anchors {
                left: parent.left; right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: units.gu(2); rightMargin: units.gu(2)
            }
            spacing: units.gu(2)

            Label {
                text: "Remove from home?"
                color: "white"
                font.bold: true
                fontSize: "large"
                width: parent.width
                wrapMode: Text.WordWrap
            }
            Label {
                text: '"' + root.appName + '" will be hidden from HomeSpike. It stays installed; you can still launch it from the swipe-left drawer.'
                color: "#cfd6e4"
                width: parent.width
                wrapMode: Text.WordWrap
            }
            Row {
                anchors.right: parent.right
                spacing: units.gu(1)
                Button {
                    text: "Cancel"
                    onClicked: root.visible = false
                }
                Button {
                    text: "Remove"
                    color: "#e94560"
                    onClicked: {
                        root.confirmed(root.appId);
                        root.visible = false;
                    }
                }
            }
        }
    }
}

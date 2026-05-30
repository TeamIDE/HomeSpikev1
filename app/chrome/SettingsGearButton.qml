/**
 * @file SettingsGearButton
 * @description Round gear button shown in the bottom-right corner while
 *   HomeSpike is in edit mode. Tapping it opens the settings overlay.
 *   Sits above the dock when the dock is enabled (caller sets the bottom
 *   offset via `bottomOffset`).
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15

Rectangle {
    id: root

    /** Whether the button should be shown. */
    property bool active: false

    /** Distance from the bottom of the parent. Caller sets to dock height
     *  + padding when the dock is enabled, smaller otherwise. */
    property real bottomOffset: units.gu(2)

    /** Emitted when the user taps the gear. */
    signal triggered()

    visible: active
    z: 200
    width: units.gu(5)
    height: width
    radius: width / 2
    color: "#3d5af1"

    Text {
        anchors.centerIn: parent
        text: "⚙"
        color: "white"
        font.pixelSize: parent.height * 0.55
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.triggered()
    }
}

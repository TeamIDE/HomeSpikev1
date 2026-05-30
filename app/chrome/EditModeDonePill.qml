/**
 * @file EditModeDonePill
 * @description "Done" pill button shown in the top-right corner while
 *   HomeSpike is in edit mode. Tapping it exits edit mode. Visibility
 *   is bound externally via the `active` property.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Rectangle {
    id: root

    /** Whether the pill should be shown. */
    property bool active: false

    /** Emitted when the user taps the pill. */
    signal dismissed()

    visible: active
    z: 200
    width: doneLabel.width + units.gu(3)
    height: units.gu(4)
    radius: height / 2
    color: "#3d5af1"

    Label {
        id: doneLabel
        anchors.centerIn: parent
        text: "Done"
        color: "white"
        font.bold: true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.dismissed()
    }
}

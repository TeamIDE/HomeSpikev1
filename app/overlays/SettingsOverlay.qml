/**
 * @file SettingsOverlay
 * @description Full-screen modal showing HomeSpike user-configurable
 *   settings: page count stepper and bottom-dock toggle. Both controls
 *   emit signals on user action — the parent owns the side effects
 *   (re-running rebuildVisible, etc.) so this module stays UI-only.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Rectangle {
    id: root

    /** Current page count (bound to persist.pageCount externally). */
    property int pageCount: 1

    /** Hard cap on page count, displayed in the help text. */
    property int maxPages: 5

    /** Current dock-enabled state (bound to persist.dockEnabled). */
    property bool dockEnabled: false

    /** Emitted when the user changes the page count via +/-. */
    signal pageCountChanged(int newCount)

    /** Emitted when the user flips the dock switch. */
    signal dockToggled(bool enabled)

    anchors.fill: parent
    z: 900
    visible: false
    color: "#aa000000"

    MouseArea {
        anchors.fill: parent
        onClicked: root.visible = false
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.85, units.gu(50))
        height: settingsCol.height + units.gu(4)
        radius: units.gu(2)
        color: "#262d4d"

        MouseArea { anchors.fill: parent }

        Column {
            id: settingsCol
            anchors {
                left: parent.left; right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: units.gu(2); rightMargin: units.gu(2)
            }
            spacing: units.gu(2)

            Label {
                text: "HomeSpike Settings"
                color: "white"
                font.bold: true
                fontSize: "large"
            }

            // ---- Pages stepper ----
            Row {
                width: parent.width
                spacing: units.gu(2)
                Column {
                    width: parent.width - pagesStepper.width - units.gu(2)
                    Label { text: "Pages"; color: "white" }
                    Label {
                        text: "Number of swipeable home screens (1–" + root.maxPages + "). When reduced, extra pages merge into the last."
                        color: "#9fa9c0"
                        fontSize: "small"
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }
                Row {
                    id: pagesStepper
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: units.gu(0.5)
                    Button {
                        text: "−"
                        width: units.gu(4)
                        enabled: root.pageCount > 1
                        onClicked: root.pageCountChanged(root.pageCount - 1)
                    }
                    Label {
                        text: root.pageCount
                        color: "white"
                        font.bold: true
                        width: units.gu(3)
                        horizontalAlignment: Text.AlignHCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Button {
                        text: "+"
                        width: units.gu(4)
                        enabled: root.pageCount < root.maxPages
                        onClicked: root.pageCountChanged(root.pageCount + 1)
                    }
                }
            }

            // ---- Dock toggle ----
            Row {
                width: parent.width
                spacing: units.gu(2)
                Column {
                    width: parent.width - dockSwitch.width - units.gu(2)
                    Label { text: "Bottom dock"; color: "white" }
                    Label {
                        text: "Up to 5 apps. Drag any tile to the dock. Turning this off returns dock apps to the last page."
                        color: "#9fa9c0"
                        fontSize: "small"
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }
                Switch {
                    id: dockSwitch
                    checked: root.dockEnabled
                    anchors.verticalCenter: parent.verticalCenter
                    onCheckedChanged: {
                        if (checked !== root.dockEnabled) root.dockToggled(checked);
                    }
                }
            }

            Row {
                anchors.right: parent.right
                Button {
                    text: "Done"
                    color: "#3d5af1"
                    onClicked: root.visible = false
                }
            }
        }
    }
}

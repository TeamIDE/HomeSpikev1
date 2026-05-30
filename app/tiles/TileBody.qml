/**
 * @file TileBody
 * @description One app tile — the icon + label + interaction surface used
 *   by both the page grids and the dock. Renders the app icon via
 *   LomiriShape (same primitive Lomiri's own drawer uses), shows a small
 *   "×" remove badge in edit mode, and routes touch into the injected
 *   DragController for drag-and-drop reordering.
 *
 *   Layout note: the tile-wide MouseArea is declared BEFORE Column on
 *   purpose. QML hit-tests siblings in declaration order with later
 *   declarations winning. Putting Column after the MouseArea means the
 *   X-badge MouseArea inside Column wins on its hit area, while taps
 *   anywhere else on the tile fall through to the tile MouseArea below.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: body

    // ---- Tile content (set by parent for each model row) ----
    property string appId:   ""
    property string appName: ""
    property string iconSrc: ""

    // ---- Source-of-truth hints for the drag controller ----
    /** Either "grid" or "dock". */
    property string container: "grid"
    /** Page index when container === "grid"; ignored for dock. */
    property int sourcePage: -1
    /** Row index within the model. */
    property int indexInModel: -1

    // ---- Injected dependencies ----
    /** Whether HomeSpike is in edit mode (controls wiggle + X badge). */
    property bool editMode: false
    /** DragController instance for routing drag events. */
    property var controller: null

    /** Emitted when the user taps the X badge. */
    signal removeRequested(string appId, string appName)

    /** Emitted on long-press while NOT in edit mode (caller should enable it). */
    signal editModeRequested()

    // ============================================================
    // Touch / drag handling (declared FIRST — see file header)
    // ============================================================
    MouseArea {
        id: tileMouse
        anchors.fill: parent
        pressAndHoldInterval: 400
        // In edit mode, claim the touch so the GridView/ListView parents
        // can't steal it as a flick before our drag threshold triggers.
        preventStealing: body.editMode

        // A tap (or jittery tap) must NOT start a drag — measure distance
        // from the press point first.
        property real pressX: 0
        property real pressY: 0
        property bool dragStarted: false
        readonly property real dragThreshold: units.gu(2)

        onClicked: {
            if (body.editMode) return;
            Qt.openUrlExternally("application:///" + body.appId + ".desktop");
        }
        onPressAndHold: {
            // Long-press outside edit mode = ask the parent to enter edit mode.
            if (!body.editMode) body.editModeRequested();
        }
        onPressed: {
            pressX = mouseX;
            pressY = mouseY;
            dragStarted = false;
            // Defensive: if a previous drag's onReleased never fired
            // (delegate destroyed during a cross-page scroll), clear
            // leftover state without persisting it.
            if (controller && controller.dragging) controller.abort();
        }
        onPositionChanged: {
            if (!body.editMode || !controller) return;
            var dx = mouseX - pressX;
            var dy = mouseY - pressY;
            if (!dragStarted) {
                if (Math.sqrt(dx*dx + dy*dy) < dragThreshold) return;
                dragStarted = true;
                var startPt = mapToItem(controller, mouseX, mouseY);
                controller.startDrag(body.container, body.sourcePage, body.indexInModel,
                                         body.appId, body.appName, body.iconSrc,
                                         startPt.x, startPt.y);
            }
            var pt = mapToItem(controller, mouseX, mouseY);
            controller.moveDrag(pt.x, pt.y);
        }
        onReleased: {
            if (controller && controller.dragging) controller.endDrag();
            dragStarted = false;
        }
        onCanceled: {
            if (controller && controller.dragging) controller.endDrag();
            dragStarted = false;
        }
    }

    // ============================================================
    // Visual content
    // ============================================================
    Column {
        anchors.centerIn: parent
        spacing: units.gu(0.5)

        Item {
            id: iconHolder
            width: units.gu(6)
            height: 7.5 / 8 * width
            anchors.horizontalCenter: parent.horizontalCenter

            LomiriShape {
                id: shape
                anchors.fill: parent
                radius: "medium"
                borderSource: "undefined"
                sourceFillMode: LomiriShape.PreserveAspectCrop
                source: Image {
                    asynchronous: true
                    sourceSize.width: shape.width
                    source: body.iconSrc
                }
                // Wiggle in edit mode (paused while a drag is in flight
                // so the dragged tile doesn't visibly jitter)
                SequentialAnimation on rotation {
                    running: body.editMode && (!controller || !controller.dragging)
                    loops: Animation.Infinite
                    NumberAnimation { from: -1.5; to: 1.5; duration: 120 }
                    NumberAnimation { from: 1.5; to: -1.5; duration: 120 }
                }
                Behavior on rotation { NumberAnimation { duration: 80 } }
            }

            // Remove badge ("×") — top-left corner, edit mode only
            Rectangle {
                visible: body.editMode
                anchors {
                    top: iconHolder.top
                    horizontalCenter: iconHolder.left
                    topMargin: -units.gu(0.5)
                }
                width: units.gu(2.5)
                height: width
                radius: width / 2
                color: "white"
                border.color: "#202840"
                border.width: 1
                z: 20

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: "#202840"
                    font.pixelSize: parent.height * 0.8
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    // Slightly larger hit target than the visible circle
                    anchors.margins: -units.gu(0.5)
                    onClicked: body.removeRequested(body.appId, body.appName)
                }
            }
        }

        Label {
            text: body.appName
            width: units.gu(9)
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
            fontSize: "x-small"
            color: "white"
            wrapMode: Text.WordWrap
            maximumLineCount: 1
            elide: Text.ElideRight
        }
    }
}

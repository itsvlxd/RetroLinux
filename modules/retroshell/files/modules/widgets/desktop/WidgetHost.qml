import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.config

// Draggable desktop widget card. Fills its positioned delegate; the delegate
// (DesktopWidgets) owns the x/y placement. In edit mode the whole card can be
// dragged; the card reports normalized (0..1) position changes which the
// delegate commits to the widget file. Each card can be locked so it cannot
// be dragged.
Item {
    id: root

    // The {id,type,x,y,width,height,locked} entry for this widget.
    property var widgetData: ({})
    // Component to render inside the card.
    property Component contentComponent: null
    // The desktop layer this widget is placed on (used for drag size math).
    property Item widgetLayer: null

    // Whether this widget is locked (cannot be dragged).
    property bool locked: root.widgetData && root.widgetData.locked === true

    // Inner margin around the content. Set to 0 to let content bleed to the
    // card edges (e.g. album-art backgrounds clipped to the rounded corners).
    property real contentMargins: 8

    // Whether the host card draws its theme border (off for borderless cards).
    property bool cardBorder: true

    // Fractional position (0..1) within the layer.
    property real normX: root.widgetData && root.widgetData.x !== undefined ? root.widgetData.x : 0.5
    property real normY: root.widgetData && root.widgetData.y !== undefined ? root.widgetData.y : 0.5

    // Live position change (every move) and final commit (on release).
    signal positionChanged(real nx, real ny)
    signal positionCommitted(real nx, real ny)
    signal requestRemove()
    signal lockToggled(bool newLocked)

    readonly property real layerW: widgetLayer ? widgetLayer.width : 0
    readonly property real layerH: widgetLayer ? widgetLayer.height : 0

    StyledRect {
        id: card
        anchors.fill: parent
        variant: "pane"
        radius: Styling.radius(6)
        enableShadow: true
        enableBorder: root.cardBorder

        Loader {
            id: contentLoader
            anchors.fill: parent
            anchors.margins: root.contentMargins
            clip: true
            sourceComponent: root.contentComponent
        }
    }

    // Whole-card drag area, active in edit mode and only when unlocked.
    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: Config.desktop.editMode && !root.locked
        cursorShape: enabled ? Qt.ClosedHandCursor : Qt.ArrowCursor

        onPressed: (mouse) => root.dragStart(mouse.x, mouse.y)
        onPositionChanged: (mouse) => root.dragMove(mouse.x, mouse.y)
        onReleased: (mouse) => root.dragEnd()
    }

    // Edit-mode chrome (border + lock + remove)
    Item {
        id: editChrome
        anchors.fill: parent
        visible: Config.desktop.editMode
        z: 10

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: card.radius
            border.color: Styling.srItem("overprimary")
            border.width: 2
            opacity: 0.8
        }

        // Lock toggle (top-left)
        StyledRect {
            id: lockBtn
            variant: root.locked ? "primary" : "common"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 6
            width: 22
            height: 22
            radius: 11
            z: 20

            Text {
                anchors.centerIn: parent
                text: root.locked ? Icons.lock : Icons.unpin
                font.family: Icons.font
                font.pixelSize: 12
                color: Styling.srItem(root.locked ? "primary" : "common")
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.locked = !root.locked;
                    root.lockToggled(root.locked);
                }
            }
        }

        // Remove button (top-right)
        StyledRect {
            id: closeBtn
            variant: "error"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            width: 22
            height: 22
            radius: 11
            z: 20

            Text {
                anchors.centerIn: parent
                text: Icons.cancel
                font.family: Icons.font
                font.pixelSize: 12
                color: Styling.srItem("error")
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.requestRemove()
            }
        }
    }

    // ── Drag logic (grab offset in the stationary layer's coordinate space) ──
    property bool dragging: false
    // Offset (in layer coords) from the widget center to the grab point.
    property real grabDX: 0
    property real grabDY: 0

    function dragStart(lx, ly) {
        dragging = true;
        if (root.widgetLayer) {
            var center = root.widgetLayer.mapFromItem(root, root.width / 2, root.height / 2);
            var grab = root.widgetLayer.mapFromItem(root, lx, ly);
            grabDX = grab.x - center.x;
            grabDY = grab.y - center.y;
        } else {
            grabDX = 0;
            grabDY = 0;
        }
    }

    function dragMove(lx, ly) {
        if (!dragging) return;
        if (root.layerW <= 0 || root.layerH <= 0) return;
        var cur = root.widgetLayer ? root.widgetLayer.mapFromItem(root, lx, ly) : Qt.point(lx, ly);
        var nx = (cur.x - grabDX) / root.layerW;
        var ny = (cur.y - grabDY) / root.layerH;
        nx = Math.max(0, Math.min(1, nx));
        ny = Math.max(0, Math.min(1, ny));
        root.normX = nx;
        root.normY = ny;
        root.positionChanged(nx, ny);
    }

    function dragEnd() {
        if (!dragging) return;
        dragging = false;
        root.positionCommitted(root.normX, root.normY);
    }
}
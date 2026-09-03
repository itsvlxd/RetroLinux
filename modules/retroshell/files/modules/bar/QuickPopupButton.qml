pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.components
import qs.modules.theme
import qs.config

Item {
    id: root

    required property var bar

    property string iconName: ""
    property string tooltipText: ""
    property string panelSource: ""
    property bool isActive: true
    property int popupWidth: 300
    property int popupHeight: 360
    property int iconPixelSize: 18

    property bool vertical: false
    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius
    property bool layerEnabled: true
    property bool hasOpened: false

    property bool isHovered: false
    readonly property bool popupOpen: popup.isOpen

    implicitWidth: 36
    implicitHeight: 36
    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    StyledToolTip {
        show: root.isHovered && !root.popupOpen
        tooltipText: root.tooltipText
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    StyledRect {
        id: buttonBg
        anchors.fill: parent
        variant: root.popupOpen ? "primary" : "bg"
        enableShadow: root.layerEnabled

        topLeftRadius: root.vertical ? root.startRadius : root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.vertical ? root.endRadius : root.endRadius

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.popupOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: root.iconName
            font.family: root.iconName.includes("<font") ? "" : Icons.font
            font.pixelSize: root.iconPixelSize
            color: root.popupOpen ? buttonBg.item : (root.isActive ? Styling.srItem("overprimary") : Colors.outline)
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.hasOpened = true;
                popup.toggle();
            }
        }
    }

    BarPopup {
        id: popup
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 14
        contentWidth: root.popupWidth
        contentHeight: root.popupHeight

        Loader {
            anchors.fill: parent
            active: root.hasOpened
            source: root.panelSource
            asynchronous: true
            onLoaded: {
                if (item && item.maxContentWidth !== undefined)
                    item.maxContentWidth = width;
                if (item && item.requestClose !== undefined)
                    item.requestClose.connect(() => { root.popup.close(); });
            }
        }
    }
}

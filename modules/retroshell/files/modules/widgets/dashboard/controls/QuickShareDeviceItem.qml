pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    required property var device

    width: parent ? parent.width : 0
    height: 44
    implicitHeight: 44

    StyledRect {
        anchors.fill: parent
        variant: mouseArea.containsMouse ? "focus" : "common"
        radius: Styling.radius(4)
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        Text {
            text: {
                var type = (root.device?.type || "").toUpperCase();
                if (type === "PHONE" || type === "FOLDABLE")
                    return Icons.phone;
                return Icons.quickshare;
            }
            font.family: Icons.font
            font.pixelSize: 20
            color: Colors.overBackground
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.device?.name ?? "Unknown device"
                font.family: Config.theme.font
                font.pixelSize: Config.theme.fontSize
                font.weight: Font.Medium
                color: Colors.overBackground
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: root.device?.address
                text: root.device?.address ?? ""
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: QuickShareService.sendTo(root.device)
    }
}

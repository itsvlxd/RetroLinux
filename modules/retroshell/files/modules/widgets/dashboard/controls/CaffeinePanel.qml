import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    signal requestClose()

    readonly property string statusText: {
        if (!CaffeineService.inhibit)
            return "Off";
        if (CaffeineService.timedMinutes > 0)
            return CaffeineService.timedMinutes + "m remaining";
        return "On (until turned off)";
    }

    function choose(minutes) {
        CaffeineService.startTimed(minutes);
        requestClose();
    }

    implicitWidth: Math.min(parent ? parent.width : 0, maxContentWidth)
    implicitHeight: column.implicitHeight + 12

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Caffeine"
                font.family: Config.theme.font
                font.pixelSize: Config.theme.fontSize
                font.bold: true
                color: Colors.overSurface
            }

            Text {
                text: "· " + root.statusText
                font.family: Config.theme.font
                font.pixelSize: Config.theme.fontSize
                color: CaffeineService.inhibit ? Styling.srItem("overprimary") : Colors.outline
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: Styling.radius(-2)
                variant: preset15Mouse.containsMouse ? "focus" : "common"

                Text {
                    anchors.centerIn: parent
                    text: "15m"
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    color: Colors.overBackground
                }

                MouseArea {
                    id: preset15Mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choose(15)
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: Styling.radius(-2)
                variant: preset30Mouse.containsMouse ? "focus" : "common"

                Text {
                    anchors.centerIn: parent
                    text: "30m"
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    color: Colors.overBackground
                }

                MouseArea {
                    id: preset30Mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choose(30)
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: Styling.radius(-2)
                variant: preset60Mouse.containsMouse ? "focus" : "common"

                Text {
                    anchors.centerIn: parent
                    text: "1h"
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    color: Colors.overBackground
                }

                MouseArea {
                    id: preset60Mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choose(60)
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: Styling.radius(-2)
                variant: preset120Mouse.containsMouse ? "focus" : "common"

                Text {
                    anchors.centerIn: parent
                    text: "2h"
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    color: Colors.overBackground
                }

                MouseArea {
                    id: preset120Mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choose(120)
                }
            }

            StyledRect {
                Layout.preferredWidth: 84
                Layout.preferredHeight: 32
                radius: Styling.radius(-2)
                variant: unlimitedMouse.containsMouse ? "primaryfocus" : "primary"

                Text {
                    anchors.centerIn: parent
                    text: "Unlimited"
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    font.bold: true
                    color: Styling.srItem("primary")
                }

                MouseArea {
                    id: unlimitedMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choose(0)
                }
            }
        }
    }
}

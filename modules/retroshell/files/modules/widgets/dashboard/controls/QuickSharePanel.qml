pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    signal requestClose

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    Component.onCompleted: {
        initialScanTimer.start();
    }

    onVisibleChanged: {
        if (visible && QuickShareService.running) {
            QuickShareService.scan();
        }
    }

    Timer {
        id: initialScanTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (QuickShareService.running) {
                QuickShareService.scan();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        PanelTitlebar {
            id: titlebar
            width: root.contentWidth
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 36
            title: "QuickShare"
            statusText: ""
            statusColor: QuickShareService.running ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
            showToggle: true
            toggleChecked: QuickShareService.running

            actions: [
                {
                    icon: Icons.gear,
                    tooltip: "Open Quick Share settings",
                    onClicked: function () {
                        Quickshell.execDetached(["retro", "settings", "quickshare"]);
                    }
                },
                {
                    icon: Icons.sync,
                    tooltip: "Scan for receiving devices",
                    enabled: true,
                    loading: QuickShareService.scanning || QuickShareService.isUpdating,
                    onClicked: function () {
                        QuickShareService.scan();
                    }
                }
            ]

            onToggleChanged: checked => {
                QuickShareService.setEnabled(checked);
                if (checked) {
                    QuickShareService.scan();
                }
            }
        }

        StyledRect {
            id: receiveRow
            width: root.contentWidth
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 26
            visible: QuickShareService.receiving
            variant: "internalbg"
            radius: Styling.radius(0)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: Icons.quickshare
                    font.family: Icons.font
                    font.pixelSize: 15
                    color: Styling.srItem("overprimary")
                }

                Text {
                    Layout.fillWidth: true
                    text: "From: " + (QuickShareService.receivingFile || "")
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overBackground
                    elide: Text.ElideRight
                }

                Text {
                    text: QuickShareService.receiveProgress + "%"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overSurfaceVariant
                }
            }
        }

        StyledRect {
            id: progressRow
            width: root.contentWidth
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 26
            visible: QuickShareService.sending
            variant: "internalbg"
            radius: Styling.radius(0)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: Icons.quickshare
                    font.family: Icons.font
                    font.pixelSize: 15
                    color: Styling.srItem("overprimary")
                }

                Text {
                    Layout.fillWidth: true
                    text: "To: " + (QuickShareService.sendingFile || "")
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overBackground
                    elide: Text.ElideRight
                }

                Text {
                    text: QuickShareService.sendProgress + "%"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overSurfaceVariant
                }
            }
        }

        StyledRect {
            id: progressBar
            width: root.contentWidth
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 6
            visible: QuickShareService.sending || QuickShareService.receiving
            variant: "internalbg"
            radius: Styling.radius(0)
            clip: true

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                width: parent.width * (QuickShareService.receiving ? QuickShareService.receiveProgress : QuickShareService.sendProgress) / 100
                color: Colors.primary

                Behavior on width {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        ListView {
            id: deviceList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            cacheBuffer: 1000
            reuseItems: true

            model: QuickShareService.deviceList

            delegate: Item {
                required property var modelData
                width: deviceList.width
                height: 44

                QuickShareDeviceItem {
                    id: deviceItem
                    width: root.contentWidth
                    height: 44
                    anchors.horizontalCenter: parent.horizontalCenter
                    device: parent.modelData
                    onSendClicked: root.requestClose()
                }
            }

            Text {
                anchors.centerIn: parent
                visible: deviceList.count === 0 && !QuickShareService.scanning
                text: QuickShareService.running ? "No devices found" : "Quick Share is off"
                font.family: Config.theme.font
                font.pixelSize: Config.theme.fontSize
                color: Colors.overSurfaceVariant
            }
        }
    }
}

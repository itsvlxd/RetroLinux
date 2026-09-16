import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.theme
import qs.config

// Bluetooth & Quick Pair card. Theme-aware. Accepts live BT telemetry via its
// properties; the widget wires it to BluetoothService.
Rectangle {
    id: root

    property bool showBackground: true
    property bool isEnabled: false
    property bool isScanning: false
    property var connectedDevices: [] // [{mac,name,type,battery}] priority-sorted
    property var pairedDevices: []    // [{mac,name,type}] paired, not connected
    property var discoveredDevices: [] // [{mac,name,type}] found while scanning
    property string priority: "automatic"

    signal toggleRequested()
    signal scanRequested()
    signal disconnectRequested(string mac)
    signal pairRequested(string mac)

    function deviceIcon(type) {
        switch (type) {
        case "audio": return Icons.headphones;
        case "keyboard": return Icons.keyboard;
        case "mouse": return Icons.mouse;
        case "gamepad": return Icons.gamepad;
        case "phone": return Icons.phone;
        case "watch": return Icons.watch;
        case "speaker": return Icons.speaker;
        case "printer": return Icons.printer;
        case "camera": return Icons.camera;
        }
        return Icons.bluetooth;
    }

    function batteryColor(b) {
        if (b < 0) return Colors.outline;
        if (b < 20) return Colors.red;
        if (b <= 50) return Colors.yellow;
        return Colors.green;
    }

    radius: 20
    clip: true

    // Theme-aware card surface
    Rectangle {
        anchors.fill: parent
        visible: root.showBackground
        radius: 20
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.surfaceContainer }
            GradientStop { position: 1.0; color: Colors.surfaceContainerLow }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 4

        // ── Header: status + scan + toggle ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: root.isEnabled
                      ? (root.connectedDevices.length > 0 ? Icons.bluetoothConnected : Icons.bluetooth)
                      : Icons.bluetoothOff
                font.family: Icons.font
                font.pixelSize: 15
                color: root.isEnabled ? Colors.primary : Colors.outline
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                Layout.fillWidth: true
                text: "Bluetooth"
                color: Colors.overBackground
                font.family: Config.theme.font
                font.pixelSize: 12
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                id: scanIcon
                Layout.alignment: Qt.AlignVCenter
                text: Icons.sync
                font.family: Icons.font
                font.pixelSize: 13
                color: root.isScanning ? Colors.primary : Colors.outline
                rotation: 0

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.scanRequested()
                }

                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    running: root.isScanning
                }
            }

            Item {
                id: toggle
                Layout.alignment: Qt.AlignVCenter
                width: 34
                height: 20

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: root.isEnabled ? Colors.primary : Colors.outlineVariant
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Rectangle {
                    id: knob
                    width: 16
                    height: 16
                    radius: width / 2
                    color: Colors.surfaceContainerLowest
                    x: root.isEnabled ? parent.width - knob.width - 2 : 2
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on x {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleRequested()
                }
            }
        }

        // ── Scrollable device list ──
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: deviceColumn.implicitHeight
            clip: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: parent.contentHeight > parent.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            ColumnLayout {
                id: deviceColumn
                width: parent.width
                spacing: 4

                // ── Connected devices ──
                Repeater {
                    model: root.connectedDevices
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 10
                        color: Colors.surfaceContainerHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: root.deviceIcon(modelData.type)
                                font.family: Icons.font
                                font.pixelSize: 15
                                color: Colors.primary
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: Colors.overBackground
                                    font.family: Config.theme.font
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.type
                                    color: Colors.outline
                                    font.family: Config.theme.font
                                    font.pixelSize: 8
                                }
                            }

                            Text {
                                visible: modelData.battery >= 0
                                text: modelData.battery + "%"
                                color: root.batteryColor(modelData.battery)
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                text: Icons.cancel
                                font.family: Icons.font
                                font.pixelSize: 12
                                color: Colors.outline
                                Layout.alignment: Qt.AlignVCenter

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.disconnectRequested(modelData.mac)
                                }
                            }
                        }
                    }
                }

                // ── Paired devices (not connected) ──
                Repeater {
                    model: root.pairedDevices
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: 10
                        color: Colors.surfaceContainerHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: root.deviceIcon(modelData.type)
                                font.family: Icons.font
                                font.pixelSize: 14
                                color: Colors.outline
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                            }

                            Text {
                                text: "Connect"
                                color: Colors.primary
                                font.family: Config.theme.font
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                Layout.alignment: Qt.AlignVCenter

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pairRequested(modelData.mac)
                                }
                            }
                        }
                    }
                }

                // ── Discovered devices (quick pair while scanning) ──
                Repeater {
                    model: root.isScanning ? root.discoveredDevices : []
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        visible: index < 3
                        radius: 10
                        color: Colors.surfaceContainerHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: root.deviceIcon(modelData.type)
                                font.family: Icons.font
                                font.pixelSize: 13
                                color: Colors.outline
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                            }

                            Text {
                                text: "Pair"
                                color: Colors.primary
                                font.family: Config.theme.font
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                Layout.alignment: Qt.AlignVCenter

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pairRequested(modelData.mac)
                                }
                            }
                        }
                    }
                }

                // ── Empty state / searching ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    visible: root.connectedDevices.length === 0 && root.pairedDevices.length === 0

                    Text {
                        Layout.fillWidth: true
                        text: !root.isEnabled ? "Bluetooth is off"
                             : root.isScanning ? "Searching…"
                             : "No devices"
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: root.isEnabled && !root.isScanning
                        text: "Scan"
                        color: Colors.primary
                        font.family: Config.theme.font
                        font.pixelSize: 10
                        font.weight: Font.Bold

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.scanRequested()
                        }
                    }
                }
            }
        }
    }
}
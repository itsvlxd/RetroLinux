import QtQuick
import QtQuick.Layouts
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

    function typeOfIcon(icon) {
        var ic = String(icon || "");
        if (ic.includes("audio-headset") || ic.includes("headphone") || ic.includes("headset")) return "audio";
        if (ic.includes("input-keyboard")) return "keyboard";
        if (ic.includes("input-mouse")) return "mouse";
        if (ic.includes("input-gaming") || ic.includes("gamepad")) return "gamepad";
        if (ic.includes("phone")) return "phone";
        if (ic.includes("watch")) return "watch";
        if (ic.includes("audio-speakers") || ic.includes("speaker")) return "speaker";
        if (ic.includes("printer")) return "printer";
        if (ic.includes("camera")) return "camera";
        return "other";
    }

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

    readonly property var mainDevice: root.connectedDevices.length > 0 ? root.connectedDevices[0] : null
    readonly property int moreCount: root.connectedDevices.length > 0 ? root.connectedDevices.length - 1 : 0
    readonly property var topPaired: root.pairedDevices.length > 0 ? root.pairedDevices[0] : null

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
        anchors.margins: 12
        spacing: 6

        // ── Header: status + scan + toggle ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: root.isEnabled
                      ? (root.mainDevice ? Icons.bluetoothConnected : Icons.bluetooth)
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

            // Scan button (spins while discovering)
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

            // iOS-style toggle
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

        // ── Main connected device pill ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            visible: root.mainDevice !== null
            radius: 12
            color: Colors.surfaceContainerHigh

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    text: root.deviceIcon(root.mainDevice ? root.mainDevice.type : "other")
                    font.family: Icons.font
                    font.pixelSize: 17
                    color: Colors.primary
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: root.mainDevice ? root.mainDevice.name : ""
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.mainDevice ? (root.mainDevice.type) : ""
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: 8
                    }
                }

                Text {
                    visible: root.mainDevice && root.mainDevice.battery >= 0
                    text: (root.mainDevice ? root.mainDevice.battery : 0) + "%"
                    color: root.mainDevice ? root.batteryColor(root.mainDevice.battery) : Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: Icons.cancel
                    font.family: Icons.font
                    font.pixelSize: 13
                    color: Colors.outline
                    Layout.alignment: Qt.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.mainDevice && root.disconnectRequested(root.mainDevice.mac)
                    }
                }
            }
        }

        // ── "+N more connected" ──
        Text {
            Layout.fillWidth: true
            visible: root.moreCount > 0
            text: "+ " + root.moreCount + " more connected"
            color: Colors.outline
            font.family: Config.theme.font
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
        }

        // ── Quick pair (paired, not connected) ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            visible: root.mainDevice === null && root.topPaired !== null && root.isEnabled
            radius: 10
            color: Colors.surfaceContainerHigh

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    text: root.deviceIcon(root.topPaired ? root.topPaired.type : "other")
                    font.family: Icons.font
                    font.pixelSize: 15
                    color: Colors.outline
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: root.topPaired ? root.topPaired.name : ""
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                Text {
                    text: "Connect"
                    color: Colors.primary
                    font.family: Config.theme.font
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.topPaired && root.pairRequested(root.topPaired.mac)
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
                visible: index < 2
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
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "Pair"
                        color: Colors.primary
                        font.family: Config.theme.font
                        font.pixelSize: 11
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
            visible: root.mainDevice === null && root.topPaired === null

            Text {
                Layout.fillWidth: true
                text: !root.isEnabled ? "Bluetooth is off"
                     : root.isScanning ? "Searching for devices…"
                     : "No devices connected"
                color: Colors.outline
                font.family: Config.theme.font
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            Text {
                visible: root.isEnabled && !root.isScanning && root.topPaired === null
                text: "Scan"
                color: Colors.primary
                font.family: Config.theme.font
                font.pixelSize: 11
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
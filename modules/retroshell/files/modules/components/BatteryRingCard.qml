import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.config

// Apple-style battery rings card. Theme-aware surface. Shows one hero device
// (square 2x2) or up to 4 devices centered in a row (wide 2x4). No placeholders.
Rectangle {
    id: root

    property bool showBackground: true
    property bool wide: false
    property var devices: [] // [{id,name,type,battery,isCharging,isConnected}]

    readonly property real ringD: root.wide ? 64 : 98
    readonly property real ringStroke: root.wide ? 6 : 8

    function ringColor(b, charging) {
        if (charging) return "#30D158";
        if (b < 10) return "#FF453A";
        if (b <= 20) return "#FFD60A";
        return "#30D158";
    }

    function deviceIcon(type) {
        switch (type) {
        case "laptop": return Icons.computer;
        case "audio":
        case "headphones": return Icons.headphones;
        case "keyboard": return Icons.keyboard;
        case "mouse":
        case "trackpad": return Icons.mouse;
        case "gamepad": return Icons.gamepad;
        case "phone": return Icons.phone;
        case "watch": return Icons.watch;
        case "speaker": return Icons.speaker;
        }
        return Icons.bluetooth;
    }

    readonly property color trackColor: Qt.rgba(
        Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.06)

    radius: 24
    clip: true

    // Matte surface
    Rectangle {
        anchors.fill: parent
        visible: root.showBackground
        radius: 24
        color: Colors.surfaceContainer
    }

    // Centered device row
    Row {
        anchors.centerIn: parent
        spacing: root.wide ? 16 : 0

        Repeater {
            model: root.devices

            delegate: Item {
                id: slotItem
                required property var modelData

                width: root.ringD + 8
                height: root.ringD + 34

                readonly property real pct: Number(modelData.battery || 0)
                readonly property bool charging: modelData.isCharging === true
                readonly property string type: String(modelData.type || "other")

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    // Ring + center icon
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: root.ringD
                        Layout.preferredHeight: root.ringD

                        Canvas {
                            id: slotRing
                            width: root.ringD
                            height: root.ringD
                            anchors.centerIn: parent

                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                var cx = width / 2, cy = height / 2;
                                var r = width / 2 - root.ringStroke / 2;

                                // Track
                                ctx.lineWidth = root.ringStroke;
                                ctx.strokeStyle = root.trackColor;
                                ctx.beginPath();
                                ctx.arc(cx, cy, r, 0, Math.PI * 2);
                                ctx.stroke();

                                // Progress arc (top, clockwise, round caps)
                                var start = -Math.PI / 2;
                                var end = start + (slotItem.pct / 100) * Math.PI * 2;
                                ctx.lineCap = "round";
                                ctx.strokeStyle = root.ringColor(slotItem.pct, slotItem.charging);

                                ctx.beginPath();
                                ctx.arc(cx, cy, r, start, end, false);
                                ctx.stroke();
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.deviceIcon(slotItem.type)
                            font.family: Icons.font
                            font.pixelSize: root.wide ? 20 : 34
                            color: Colors.overBackground
                        }
                    }

                    // Percentage label (with charging bolt)
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 3

                        Text {
                            visible: slotItem.charging
                            text: Icons.lightning
                            font.family: Icons.font
                            font.pixelSize: root.wide ? 11 : 14
                            color: "#30D158"
                        }

                        Text {
                            text: Math.round(slotItem.pct) + "%"
                            color: Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: root.wide ? 14 : 20
                            font.weight: Font.Bold
                        }
                    }

                    // Device name
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        text: slotItem.modelData.name || ""
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: root.wide ? 9 : 11
                        opacity: 0.7
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
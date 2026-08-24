import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.config

// Power Profiles & Thermals card. Theme-aware. Accepts live telemetry + a
// profile list; emits profileSelected(id) when the user picks a profile.
Rectangle {
    id: root

    property bool showBackground: true
    property string variant: "compact"
    property string activeProfile: ""
    property real powerDrawWatts: 0
    property int cpuTempC: -1
    property int gpuTempC: -1
    property int diskTempC: -1
    property int fanSpeedRpm: -1
    property var profiles: []

    signal profileSelected(string id)

    function tempColor(t) {
        if (t < 0) return Colors.overBackground;
        if (t < 60) return Colors.green;
        if (t < 80) return Colors.orange;
        return Colors.red;
    }

    function fanColor(rpm) {
        if (rpm < 0) return Colors.overBackground;
        if (rpm < 2000) return Colors.green;
        if (rpm <= 3200) return Colors.orange;
        return Colors.red;
    }

    // Telemetry cells; the GPU cell is omitted when there's no reading (the
    // SSD temp is shown in its place).
    function telemetryModel() {
        var items = [
            { icon: Icons.thermometer, label: "CPU", value: root.cpuTempC >= 0 ? root.cpuTempC + "°C" : "—°C", color: root.tempColor(root.cpuTempC) }
        ];
        if (root.gpuTempC >= 0) {
            items.push({ icon: Icons.gpu, label: "GPU", value: root.gpuTempC + "°C", color: root.tempColor(root.gpuTempC) });
        } else if (root.diskTempC >= 0) {
            items.push({ icon: Icons.disk, label: "SSD", value: root.diskTempC + "°C", color: root.tempColor(root.diskTempC) });
        }
        items.push({
            icon: Icons.sync,
            label: root.fanSpeedRpm > 0 ? "RPM" : "Fan",
            value: root.fanSpeedRpm > 0 ? root.formatRpm(root.fanSpeedRpm) : "Quiet",
            color: root.fanColor(root.fanSpeedRpm)
        });
        return items;
    }

    function formatRpm(v) {
        var s = String(v);
        var out = "";
        while (s.length > 3) {
            out = "," + s.slice(-3) + out;
            s = s.slice(0, -3);
        }
        return s + out;
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

    Loader {
        anchors.fill: parent
        sourceComponent: root.variant === "mini" ? miniLayout : compactLayout
    }

    Component {
        id: compactLayout
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

        // ── Header: title + live power draw ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: Icons.lightning
                font.family: Icons.font
                font.pixelSize: 14
                color: Colors.primary
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                Layout.fillWidth: true
                text: "Power"
                color: Colors.overBackground
                font.family: Config.theme.font
                font.pixelSize: 12
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 18
                Layout.preferredWidth: wattText.implicitWidth + 12
                radius: 9
                color: Colors.surfaceContainerHigh

                Text {
                    id: wattText
                    anchors.centerIn: parent
                    text: root.powerDrawWatts > 0 ? Math.round(root.powerDrawWatts) + " W" : "—"
                    color: Colors.primary
                    font.family: Config.theme.font
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
            }
        }

        // ── Telemetry grid (CPU / GPU / Fan) ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: [
                    { icon: Icons.thermometer, label: "CPU", value: root.cpuTempC >= 0 ? root.cpuTempC + "°C" : "—°C", color: root.tempColor(root.cpuTempC) },
                    { icon: Icons.gpu, label: "GPU", value: root.gpuTempC >= 0 ? root.gpuTempC + "°C" : "—°C", color: root.tempColor(root.gpuTempC) },
                    { icon: Icons.sync, label: root.fanSpeedRpm > 0 ? "RPM" : "Fan", value: root.fanSpeedRpm > 0 ? root.formatRpm(root.fanSpeedRpm) : "Quiet", color: Colors.overBackground }
                ]

                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: modelData.icon
                        font.family: Icons.font
                        font.pixelSize: 13
                        color: modelData.color
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: modelData.value
                        color: modelData.color
                        font.family: Config.theme.font
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: modelData.label
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: 8
                    }
                }
            }
        }

        // ── Profile switcher ──
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 4

            Repeater {
                model: root.profiles
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34

                    readonly property bool isActive: root.activeProfile === modelData.id

                    radius: 10
                    color: isActive ? Colors.primary : Colors.surfaceContainerHigh

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 1

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.icon
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: isActive ? Colors.surfaceContainerLowest : Colors.outline
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            color: isActive ? Colors.surfaceContainerLowest : Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: 8
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            Layout.maximumWidth: 60
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!isActive)
                                root.profileSelected(modelData.id)
                        }
                    }
                }
            }
        }
    }
    }

    // ── 1x3 mini (240x80): header + profile pills ──
    Component {
        id: miniLayout
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: Icons.lightning
                    font.family: Icons.font
                    font.pixelSize: 12
                    color: Colors.primary
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: "Power"
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: root.cpuTempC >= 0 ? root.cpuTempC + "°C" : ""
                    color: root.tempColor(root.cpuTempC)
                    font.family: Config.theme.font
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 17
                    Layout.preferredWidth: miniWattText.implicitWidth + 10
                    radius: 9
                    color: Colors.surfaceContainerHigh

                    Text {
                        id: miniWattText
                        anchors.centerIn: parent
                        text: root.powerDrawWatts > 0 ? Math.round(root.powerDrawWatts) + " W" : "—"
                        color: Colors.primary
                        font.family: Config.theme.font
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: root.profiles
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28

                        readonly property bool isActive: root.activeProfile === modelData.id

                        radius: 9
                        color: isActive ? Colors.primary : Colors.surfaceContainerHigh

                        Behavior on color {
                            ColorAnimation { duration: 200 }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 0

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.icon
                                font.family: Icons.font
                                font.pixelSize: 13
                                color: isActive ? Colors.surfaceContainerLowest : Colors.outline
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.label
                                color: isActive ? Colors.surfaceContainerLowest : Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 8
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                Layout.maximumWidth: 64
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!isActive)
                                    root.profileSelected(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
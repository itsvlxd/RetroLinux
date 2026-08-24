import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config
import qs.modules.widgets.desktop

// Desktop battery widget — 2x2 (160x160) card.
// Multiple faces switchable via a gear button: gauge, juice, bars.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    property string face: "gauge"
    signal faceSelected(string face)

    onWidgetDataChanged: {
        root.face = (root.widgetData && root.widgetData.face) ? root.widgetData.face : "gauge";
    }

    function setFace(f) {
        root.face = f;
        root.faceSelected(f);
    }

    function openFaceMenu() {
        var faces = ["gauge", "juice", "bars"];
        var labels = ["Gauge", "Juice", "Bars"];
        var items = [];
        for (var i = 0; i < faces.length; i++) {
            (function (f, l) {
                items.push({
                    text: (root.face === f ? "✓ " : "") + l,
                    isSeparator: false,
                    onTriggered: function () { root.setFace(f); }
                });
            })(faces[i], labels[i]);
        }
        Visibilities.contextMenu.openCustomMenu(items, 160, 32, "battery");
    }

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            function batteryColor() {
                if (!Battery.available)
                    return Colors.overBackground;
                var pct = Battery.percentage;
                if (pct <= 15)
                    return Colors.red;
                if (pct >= 85)
                    return Colors.green;
                var ratio = (pct - 15) / (85 - 15);
                return Qt.rgba(
                    Colors.red.r + (Colors.green.r - Colors.red.r) * ratio,
                    Colors.red.g + (Colors.green.g - Colors.red.g) * ratio,
                    Colors.red.b + (Colors.green.b - Colors.red.b) * ratio,
                    1
                );
            }

            // Black/white foreground that contrasts with the liquid color.
            function contrastColor() {
                var c = content.batteryColor();
                var lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
                return lum > 0.5 ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(1, 1, 1, 0.92);
            }

            // Whether the liquid has risen past the centered text block.
            property bool textOnLiquid: root.face === "juice" && content.height > 0 &&
                (content.height * (100 - Battery.percentage) / 100) <= content.height / 2

            // Base card background (clipped to the card's rounded corners)
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Colors.surfaceContainer }
                    GradientStop { position: 1.0; color: Colors.surfaceContainerLow }
                }
            }

            // ── Juice face: liquid fills the whole widget background ──
            Rectangle {
                visible: root.face === "juice"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * (Battery.percentage / 100)
                color: content.batteryColor()
                opacity: 0.7

                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }
            }

            WavyLine {
                visible: root.face === "juice"
                anchors.left: parent.left
                anchors.right: parent.right
                y: parent.height * (100 - Battery.percentage) / 100 - height / 2
                height: 16
                color: content.batteryColor()
                lineWidth: 3
                amplitudeMultiplier: 0.6
                frequency: 3
                running: true
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 6

                // ── Face: gauge (battery body with fill) ──
                Item {
                    visible: root.face === "gauge"
                    Layout.alignment: Qt.AlignHCenter
                    width: 84
                    height: 44

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Colors.surfaceContainerHighest
                        border.color: Colors.outlineVariant
                        border.width: 2
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 3
                        width: (parent.width - 6) * (Battery.percentage / 100)
                        radius: 3
                        color: Battery.percentage > 20 ? Colors.primary : Colors.error
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: -5
                        width: 5
                        height: 16
                        radius: 2
                        color: Colors.outlineVariant
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Battery.isCharging ? Icons.lightning : ""
                        font.family: Icons.font
                        font.pixelSize: 24
                        color: Battery.isCharging ? Colors.overSurface : "transparent"
                        visible: Battery.isCharging
                    }
                }

                // ── Face: bars (segmented line bar across the width) ──
                Item {
                    id: barsFace
                    visible: root.face === "bars"
                    Layout.alignment: Qt.AlignHCenter
                    width: 128
                    height: 18

                    readonly property int barSegments: 26
                    readonly property int filledSegments: Math.round(Battery.percentage / 100 * barSegments)

                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        color: Colors.surfaceContainerHighest
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 2

                        Repeater {
                            model: barsFace.barSegments
                            delegate: Rectangle {
                                width: 3
                                height: 18
                                radius: 1.5
                                color: index < barsFace.filledSegments
                                       ? content.batteryColor()
                                       : Colors.surfaceContainerLow
                            }
                        }
                    }
                }

                // Percentage
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Battery.available ? Math.round(Battery.percentage) + "%" : "--%"
                    color: content.textOnLiquid ? content.contrastColor() : Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 28
                    font.weight: Font.Bold
                }

                // State
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Battery.isCharging ? "Charging"
                         : Battery.isPluggedIn ? "Plugged in"
                         : Battery.available ? "On battery"
                         : "No battery"
                    color: content.textOnLiquid ? content.contrastColor() : Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: 12
                }
            }

            // Settings gear (edit mode only)
            StyledRect {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 6
                width: 22
                height: 22
                radius: 11
                variant: gearHover.hovered ? "focus" : "common"
                z: 20
                visible: Config.desktop.editMode

                Text {
                    anchors.centerIn: parent
                    text: Icons.gear
                    font.family: Icons.font
                    font.pixelSize: 12
                    color: Styling.srItem("common")
                }

                MouseArea {
                    id: gearHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openFaceMenu()
                }
            }
        }
    }
}
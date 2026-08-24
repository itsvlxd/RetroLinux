import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.config

// Apple-style "Device Storage" card. Theme-aware (uses Colors variants).
// segments: array of {label, sizeGB, color, striped|hasStripes}.
Rectangle {
    id: root

    property bool showBackground: true
    property string title: "Device Storage"
    property var segments: []
    property real totalGB: 512
    property real gapSize: 3
    property int padding: 16

    readonly property real usedGB: {
        var s = 0;
        for (var i = 0; i < root.segments.length; i++)
            s += Number(root.segments[i].sizeGB || 0);
        return s;
    }

    radius: 20
    clip: true

    // Theme-aware card surface (hidden when hosted inside WidgetHost)
    Rectangle {
        anchors.fill: parent
        visible: root.showBackground
        radius: 20
        border.color: Colors.outlineVariant
        border.width: 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.surfaceContainer }
            GradientStop { position: 1.0; color: Colors.surfaceContainerLow }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 6

        // Header subtitle
        Text {
            text: root.title
            color: Colors.outline
            font.family: Config.theme.font
            font.pixelSize: 10
            font.weight: Font.Medium
        }

        // Stat line: used (bold) + total (muted, baseline-aligned)
        RowLayout {
            spacing: 4

            Text {
                text: Math.round(root.usedGB) + " GB"
                color: Colors.overBackground
                font.family: Config.theme.font
                font.pixelSize: 20
                font.weight: Font.Bold
            }

            Text {
                text: "/ " + Math.round(root.totalGB) + " GB"
                color: Colors.outline
                font.family: Config.theme.font
                font.pixelSize: 12
                Layout.alignment: Qt.AlignBaseline
            }
        }

        // Multi-segment progress bar
        Rectangle {
            id: track
            Layout.fillWidth: true
            height: 9
            radius: height / 2
            color: Colors.surfaceContainerHigh
            border.color: Colors.outlineVariant
            border.width: 1
            clip: true

            Row {
                id: segRow
                anchors.fill: parent
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                spacing: root.gapSize

                Repeater {
                    model: root.segments
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: {
                            var total = 0;
                            for (var i = 0; i < root.segments.length; i++)
                                total += Number(root.segments[i].sizeGB || 0);
                            if (total <= 0) return 0;
                            var usable = segRow.width - (root.segments.length - 1) * segRow.spacing;
                            return Math.max(0, usable * (Number(root.segments[index].sizeGB || 0) / total));
                        }
                        height: segRow.height

                        Rectangle {
                            id: segBody
                            anchors.fill: parent
                            radius: height / 2
                            color: Qt.color(modelData.color || Colors.primary)
                            clip: true

                            // Subtle 45° diagonal stripe overlay (prominent on striped)
                            Canvas {
                                anchors.fill: parent
                                visible: segBody.width > 0
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                Component.onCompleted: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    var striped = modelData.striped === true || modelData.hasStripes === true;
                                    var stripeSpacing = 7;
                                    ctx.strokeStyle = Qt.rgba(0, 0, 0, striped ? 0.30 : 0.12);
                                    ctx.lineWidth = 2.5;
                                    ctx.beginPath();
                                    for (var x = -height; x < width + height; x += stripeSpacing) {
                                        ctx.moveTo(x, height);
                                        ctx.lineTo(x + height, 0);
                                    }
                                    ctx.stroke();
                                }
                            }
                        }
                    }
                }
            }
        }

        // Category legend (2x2 grid)
        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            columns: 2
            columnSpacing: 10
            rowSpacing: 3

            Repeater {
                model: root.segments
                delegate: RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 40
                    spacing: 5

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: Qt.color(modelData.color || Colors.primary)
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: modelData.label
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }
    }
}
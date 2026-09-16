import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.config

// Apple-style "Device Storage" card. Theme-aware (uses Colors variants).
// segments: array of {label, sizeGB, color, striped|hasStripes}.
Rectangle {
    id: root

    property bool showBackground: true
    property bool wide: false
    property bool showBorder: true
    property string title: "Device Storage"
    property var segments: []
    property real totalGB: 512
    // Header used value; -1 = compute from segment sizes.
    property real usedGB: -1
    property real gapSize: 3
    property int padding: 16

    readonly property real computedUsedGB: {
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
        border.width: root.showBorder ? 1 : 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.surfaceContainer }
            GradientStop { position: 1.0; color: Colors.surfaceContainerLow }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 6

        // Header: title left, stat right (wide) / title alone (compact)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: root.title
                color: Colors.outline
                font.family: Config.theme.font
                font.pixelSize: root.wide ? 12 : 10
                font.weight: Font.Medium
                Layout.fillWidth: root.wide
                elide: Text.ElideRight
            }

            // Stat line (wide, right-aligned)
            RowLayout {
                visible: root.wide
                Layout.alignment: Qt.AlignRight
                spacing: 4

                Text {
                    text: {
                        var gb = root.usedGB >= 0 ? root.usedGB : root.computedUsedGB;
                        return (gb < 10 ? gb.toFixed(1) : Math.round(gb)) + " GB";
                    }
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }

                Text {
                    text: "/ " + (root.totalGB < 10 ? root.totalGB.toFixed(1) : Math.round(root.totalGB)) + " GB"
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignBaseline
                }
            }
        }

        // Stat line (compact): used (bold) + total (muted, baseline-aligned)
        RowLayout {
            visible: !root.wide
            spacing: 4

            Text {
                text: {
                    var gb = root.usedGB >= 0 ? root.usedGB : root.computedUsedGB;
                    return (gb < 10 ? gb.toFixed(1) : Math.round(gb)) + " GB";
                }
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
            height: 30
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
                            anchors.fill: parent
                            radius: 6
                            color: Qt.color(modelData.color || Colors.primary)
                        }
                    }
                }
            }
        }

        // Category legend (2x2 grid compact / single row wide)
        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            columns: root.wide ? root.segments.length : 2
            columnSpacing: root.wide ? 4 : 10
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

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: {
                                var gb = Number(modelData.sizeGB || 0);
                                return gb > 0 ? modelData.label : "Unknown";
                            }
                            color: Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: root.wide ? 10 : 10
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            visible: root.wide
                            text: {
                                var gb = Number(modelData.sizeGB || 0);
                                return gb > 0 ? (gb < 10 ? gb.toFixed(1) : Math.round(gb)) + " GB" : "—";
                            }
                            color: Qt.color(modelData.color || Colors.primary)
                            font.family: Config.theme.font
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
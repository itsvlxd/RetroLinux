import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.config

// DEV.to developer feed card. Theme-aware. Shows one featured article (square
// 2x2) or three stacked articles (wide 2x4). Clicking an article opens it.
Rectangle {
    id: root

    property bool showBackground: true
    property bool wide: false
    property var articles: [] // [{title,url,reading_time_minutes,public_reactions_count,username}]
    property string tag: "linux"

    radius: 20
    clip: true

    // Theme-aware surface
    Rectangle {
        anchors.fill: parent
        visible: root.showBackground
        radius: 20
        color: Colors.surfaceContainer
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.wide ? 10 : 12
        spacing: 5

        // ── Header ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 7

            // DEV brand badge
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 32
                height: 18
                radius: 9
                color: "#FFFFFF"

                Text {
                    anchors.centerIn: parent
                    text: "DEV"
                    color: "#000000"
                    font.family: Config.theme.font
                    font.pixelSize: 10
                    font.weight: Font.Black
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Developer Feed"
                color: Colors.overBackground
                font.family: Config.theme.font
                font.pixelSize: 13
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.alignment: Qt.AlignVCenter
            }

            // Active tag pill
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: root.tag.length > 0
                height: 18
                width: tagText.implicitWidth + 12
                radius: 9
                color: Colors.surfaceContainerHigh

                Text {
                    id: tagText
                    anchors.centerIn: parent
                    text: "#" + root.tag
                    color: Colors.cyan
                    font.family: Config.theme.font
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
            }
        }

        // ── Article capsules ──
        Repeater {
            model: root.articles

            delegate: Rectangle {
                id: capsule
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.fillHeight: !root.wide
                Layout.preferredHeight: root.wide ? 34 : 0
                Layout.maximumHeight: root.wide ? 34 : 1000

                radius: 12
                color: Colors.surfaceContainerHigh

                property bool hovered: false
                border.color: capsule.hovered ? Colors.primary : "transparent"
                border.width: 1

                Behavior on border.color {
                    ColorAnimation { duration: 120 }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: capsule.hovered = true
                    onExited: capsule.hovered = false
                    onClicked: Qt.openUrlExternally(modelData.url)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: root.wide ? 4 : 8
                    anchors.bottomMargin: root.wide ? 4 : 8
                    spacing: 2

                    // Title (2-line clamp on square, 1-line on wide)
                    Text {
                        Layout.fillWidth: true
                        text: modelData.title || ""
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: root.wide ? 12 : 14
                        font.weight: Font.Bold
                        maximumLineCount: root.wide ? 1 : 2
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                    }

                    // Meta row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Text {
                            text: "@" + (modelData.username || "dev")
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        Text {
                            text: "·"
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: 10
                        }

                        Text {
                            text: Icons.clock
                            font.family: Icons.font
                            font.pixelSize: 10
                            color: Colors.outline
                        }

                        Text {
                            text: (modelData.reading_time_minutes || 0) + " min read"
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: 10
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: Icons.heart
                            font.family: Icons.font
                            font.pixelSize: 11
                            color: Colors.magenta
                        }

                        Text {
                            text: modelData.public_reactions_count || 0
                            color: Colors.magenta
                            font.family: Config.theme.font
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }

        // ── Empty / loading state ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.articles.length === 0

            Text {
                anchors.centerIn: parent
                text: "No articles yet — check your connection"
                color: Colors.outline
                font.family: Config.theme.font
                font.pixelSize: 11
            }
        }
    }
}
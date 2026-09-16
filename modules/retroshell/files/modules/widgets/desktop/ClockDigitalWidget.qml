import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config
import qs.modules.widgets.desktop

// Desktop digital clock — 2x2 (160x160) card with time + date.
// Multiple styles switchable via a gear button: classic, minimal, compact, large.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    property string face: "classic"
    signal faceSelected(string face)

    onWidgetDataChanged: {
        root.face = (root.widgetData && root.widgetData.face) ? root.widgetData.face : "classic";
    }

    function setFace(f) {
        root.face = f;
        root.faceSelected(f);
    }

    function openFaceMenu() {
        var faces = ["classic", "minimal", "compact", "large"];
        var labels = ["Classic", "Minimal", "Compact", "Large"];
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
        Visibilities.contextMenu.openCustomMenu(items, 170, 32, "clock");
    }

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            property string timeText: ""
            property string secText: ""
            property string dateText: ""

            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    var now = new Date();
                    var fmt = Config.bar.use12hFormat ? "h:mm" : "HH:mm";
                    content.timeText = Qt.formatDateTime(now, fmt);
                    content.secText = Qt.formatDateTime(now, Config.bar.use12hFormat ? "ss ap" : "ss");
                    content.dateText = Qt.formatDateTime(now, "ddd, MMM d");
                }
            }

            // Card background
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Colors.surfaceContainer }
                    GradientStop { position: 1.0; color: Colors.surfaceContainerLow }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 3

                    Text {
                        text: content.timeText
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: root.face === "large" ? 52 : 40
                        font.weight: Font.Bold
                    }

                    Text {
                        visible: root.face !== "minimal" && root.face !== "compact"
                        text: content.secText
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 8
                    }
                }

                Text {
                    visible: root.face !== "minimal"
                    text: content.dateText
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 13
                    opacity: 0.7
                    Layout.alignment: Qt.AlignHCenter
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
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.modules.globals
import qs.config

PanelWindow {
    id: root

    property ShellScreen targetScreen
    screen: targetScreen

    property real radius: Styling.radius(16)
    property real artRadius: Styling.radius(6)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "retroshell:mediaosd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    WlrLayershell.margins.bottom: 100

    color: "transparent"

    visible: GlobalStates.mediaOsdVisible

    readonly property var player: MprisController.activePlayer
    readonly property bool hasActivePlayer: player !== null
    readonly property string artUrl: (player?.trackArtUrl ?? "") || ""
    readonly property bool hasArtwork: artUrl !== ""

    readonly property string actionIcon: {
        if (GlobalStates.mediaOsdAction === "next")
            return Icons.next;
        if (GlobalStates.mediaOsdAction === "prev")
            return Icons.previous;
        return MprisController.isPlaying ? Icons.pause : Icons.play;
    }

    Item {
        anchors.fill: parent

        StyledRect {
            id: pill
            variant: "popup"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            implicitWidth: 284
            implicitHeight: 76
            radius: root.radius
            clip: true

            Image {
                id: artBgImage
                anchors.fill: parent
                source: root.artUrl
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectCrop
                visible: root.hasArtwork
                asynchronous: true
            }

            MultiEffect {
                anchors.fill: parent
                source: artBgImage
                blurEnabled: true
                blurMax: 32
                blur: 1.0
                visible: root.hasArtwork
                opacity: 0.45

                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.42
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                spacing: 12

                ClippingRectangle {
                    id: artClip
                    Layout.alignment: Qt.AlignVCenter
                    width: 48
                    height: 48
                    radius: root.artRadius
                    color: Colors.surface

                    Image {
                        anchors.fill: parent
                        source: root.artUrl
                        sourceSize: Qt.size(128, 128)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Icons.player
                        font.family: Icons.font
                        font.pixelSize: 20
                        color: Colors.overBackground
                        visible: !root.hasArtwork
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: "Now playing"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.bold: true
                        color: Colors.primary
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            if (!root.hasActivePlayer)
                                return "Nothing Playing";
                            const title = root.player.trackTitle || "Unknown";
                            const artist = root.player.trackArtist || "";
                            return artist ? (title + " - " + artist) : title;
                        }
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(1)
                        font.bold: true
                        color: Colors.overBackground
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                Item {
                    Layout.alignment: Qt.AlignVCenter
                    width: 44
                    height: 44

                    StyledRect {
                        anchors.fill: parent
                        variant: "primary"
                        radius: height / 2

                        Text {
                            anchors.centerIn: parent
                            text: root.actionIcon
                            font.family: Icons.font
                            font.pixelSize: 22
                            color: parent.item
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onEntered: {
            hideTimer.stop();
            hideTimer.triggered();
        }
        hoverEnabled: true
    }

    Timer {
        id: hideTimer
        interval: 2500
        onTriggered: GlobalStates.mediaOsdVisible = false
    }

    Connections {
        target: GlobalStates
        function onMediaOsdVisibleChanged() {
            if (GlobalStates.mediaOsdVisible) {
                hideTimer.restart();
            }
        }
    }
}

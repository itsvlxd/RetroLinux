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

    readonly property int borderWidth: Config.theme && Config.theme.srPopup && Config.theme.srPopup.border ? Config.theme.srPopup.border[1] : 2

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

    readonly property string headerText: {
        const action = GlobalStates.mediaOsdAction;
        if (action === "next")
            return "Next";
        if (action === "prev")
            return "Previous";
        return MprisController.isPlaying ? "Now playing" : "Paused";
    }

    Item {
        anchors.fill: parent

        StyledRect {
            id: pill
            variant: "popup"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            implicitWidth: 220
            implicitHeight: 52
            radius: root.radius
            clip: true
            enableBorder: false

            Image {
                id: artBgImage
                anchors.fill: parent
                anchors.margins: root.borderWidth
                source: root.artUrl
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectCrop
                visible: root.hasArtwork
                asynchronous: true
            }

            MultiEffect {
                anchors.fill: parent
                anchors.margins: root.borderWidth
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
                anchors.margins: root.borderWidth
                color: "black"
                opacity: 0.50
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                spacing: 8

                ClippingRectangle {
                    id: artClip
                    Layout.alignment: Qt.AlignVCenter
                    width: 40
                    height: 40
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
                        text: root.headerText
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
            }

            ClippingRectangle {
                anchors.fill: parent
                radius: root.radius
                color: "transparent"
                border.color: Colors.surfaceBright
                border.width: 2
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
        interval: 4000
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

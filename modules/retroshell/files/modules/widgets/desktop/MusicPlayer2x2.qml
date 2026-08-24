import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.modules.theme
import qs.modules.services
import qs.modules.globals
import qs.modules.components
import qs.config
import qs.modules.widgets.desktop

// Desktop music player — square (2x2) card, 160x160 (1 grid unit = 80px).
// Album cover fills the whole card (rounded corners), info + controls overlaid.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            readonly property bool hasActivePlayer: MprisController.activePlayer !== null
            readonly property bool isPlaying: MprisController.activePlayer?.playbackState === MprisPlaybackState.Playing
            readonly property real position: MprisController.activePlayer?.position ?? 0.0
            readonly property real length: MprisController.activePlayer?.length ?? 1.0
            readonly property bool hasArtwork: (MprisController.activePlayer?.trackArtUrl ?? "") !== ""
            readonly property string artwork: content.hasArtwork ? MprisController.activePlayer.trackArtUrl : content.wallpaperPath
            readonly property string wallpaperPath: {
                if (typeof GlobalStates === "undefined" || !GlobalStates.wallpaperManager) return "";
                let path = GlobalStates.wallpaperManager.currentWallpaper;
                let frame = GlobalStates.wallpaperManager.getLockscreenFramePath(path);
                return frame ? "file://" + frame : "";
            }

            function formatTime(seconds) {
                const total = Math.floor(seconds);
                const m = Math.floor((total % 3600) / 60);
                const s = total % 60;
                return m + ":" + (s < 10 ? "0" : "") + s;
            }

            // Full-card album cover background
            Image {
                id: bgArt
                anchors.fill: parent
                source: content.artwork
                sourceSize: Qt.size(160, 160)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
            }

            // Dim overlay
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.5) }
                    GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.2) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.6) }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 3

                // Top row: player source icon (top-right)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Item { Layout.fillWidth: true }

                    Text {
                        text: content.hasActivePlayer ? root.getPlayerIcon(MprisController.activePlayer) : Icons.player
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: "#ffffff"
                        opacity: content.hasActivePlayer ? 0.9 : 0.4
                        layer.enabled: true
                        layer.effect: BgShadow {}
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -5
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MprisController.cyclePlayer(1)
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                // Title
                Text {
                    Layout.fillWidth: true
                    text: content.hasActivePlayer ? (MprisController.activePlayer?.trackTitle ?? "Unknown") : "Nothing Playing"
                    color: "#ffffff"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(1)
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 1
                    layer.enabled: true
                    layer.effect: BgShadow {}
                }

                // Artist
                Text {
                    Layout.fillWidth: true
                    text: content.hasActivePlayer ? (MprisController.activePlayer?.trackArtist ?? "") : "Enjoy the silence"
                    color: Qt.rgba(1, 1, 1, 0.85)
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 1
                    layer.enabled: true
                    layer.effect: BgShadow {}
                }

                // Seek row: time — slider — time
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: content.hasActivePlayer ? content.formatTime(content.position) : "--:--"
                        color: Qt.rgba(1, 1, 1, 0.75)
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-3)
                        layer.enabled: true
                        layer.effect: BgShadow {}
                    }

                    PositionSlider {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 5
                        player: MprisController.activePlayer
                        useCustomColors: true
                        customProgressColor: Colors.primary
                    }

                    Text {
                        text: content.hasActivePlayer ? content.formatTime(content.length) : "--:--"
                        color: Qt.rgba(1, 1, 1, 0.75)
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-3)
                        layer.enabled: true
                        layer.effect: BgShadow {}
                    }
                }

                // Controls
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: Icons.previous
                        font.family: Icons.font
                        font.pixelSize: 18
                        color: MprisController.canGoPrevious ? "#ffffff" : Qt.rgba(1, 1, 1, 0.4)
                        layer.enabled: true
                        layer.effect: BgShadow {}
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            enabled: MprisController.canGoPrevious
                            onClicked: MprisController.previous()
                        }
                    }

                    StyledRect {
                        id: playBtn
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 17
                        variant: "primary"
                        opacity: content.hasActivePlayer ? 1.0 : 0.5

                        Text {
                            anchors.centerIn: parent
                            text: content.isPlaying ? Icons.pause : Icons.play
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: playBtn.item
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: content.hasActivePlayer
                            onClicked: MprisController.togglePlaying()
                        }
                    }

                    Text {
                        text: Icons.next
                        font.family: Icons.font
                        font.pixelSize: 18
                        color: MprisController.canGoNext ? "#ffffff" : Qt.rgba(1, 1, 1, 0.4)
                        layer.enabled: true
                        layer.effect: BgShadow {}
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            enabled: MprisController.canGoNext
                            onClicked: MprisController.next()
                        }
                    }
                }
            }
        }
    }

    // Player icon lookup (same as CompactPlayer)
    function getPlayerIcon(player) {
        if (!player)
            return Icons.player;
        const dbusName = (player.dbusName || "").toLowerCase();
        const desktopEntry = (player.desktopEntry || "").toLowerCase();
        const identity = (player.identity || "").toLowerCase();
        if (dbusName.includes("spotify") || desktopEntry.includes("spotify") || identity.includes("spotify"))
            return Icons.spotify;
        if (dbusName.includes("chromium") || dbusName.includes("chrome") || desktopEntry.includes("chromium") || desktopEntry.includes("chrome"))
            return Icons.chromium;
        if (dbusName.includes("firefox") || desktopEntry.includes("firefox"))
            return Icons.firefox;
        if (dbusName.includes("telegram") || desktopEntry.includes("telegram") || identity.includes("telegram"))
            return Icons.telegram;
        return Icons.player;
    }
}
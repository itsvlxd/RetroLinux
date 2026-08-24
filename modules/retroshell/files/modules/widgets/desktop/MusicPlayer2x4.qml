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

// Desktop music player — wide (2x4) card, 320x160 (1 grid unit = 80px).
// Album cover fills the whole background; circular seek disc on the left and
// controls on the right.
WidgetHost {
    id: root

    implicitWidth: 320
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
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
                    GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.3) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.65) }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 12

                // ── Left: circular seek disc ──
                Item {
                    Layout.preferredWidth: 136
                    Layout.preferredHeight: 136
                    Layout.alignment: Qt.AlignVCenter

                    CircularSeekBar {
                        id: disc
                        anchors.fill: parent
                        value: content.length > 0 ? content.position / content.length : 0
                        accentColor: Colors.primary
                        trackColor: Qt.rgba(1, 1, 1, 0.25)
                        lineWidth: 6
                        ringPadding: 12
                        handleSpacing: 20
                        startAngleDeg: 180
                        spanAngleDeg: 180
                        wavy: Config.performance.wavyLine
                        waveAmplitude: content.isPlaying ? 2 : 0
                        waveFrequency: 24
                        enabled: content.hasActivePlayer && (MprisController.activePlayer?.canSeek ?? false)

                        onValueEdited: newValue => {
                            if (MprisController.activePlayer && MprisController.activePlayer.canSeek) {
                                MprisController.activePlayer.position = newValue * content.length;
                            }
                        }

                        // Spinning CD (cover art) in the middle — bounces back to rest on stop
                        Item {
                            id: cdContainer
                            anchors.centerIn: parent
                            width: parent.width - 56
                            height: parent.height - 56

                            property real cdRotation: 0
                            rotation: cdRotation

                            // Continuous spin while playing
                            NumberAnimation {
                                id: spinAnim
                                target: cdContainer
                                property: "cdRotation"
                                duration: 8000
                                loops: Animation.Infinite
                            }

                            // Bounce back into position when playback stops
                            // (same OutBack overshoot as CompactPlayer)
                            NumberAnimation {
                                id: bounceBackAnim
                                target: cdContainer
                                property: "cdRotation"
                                duration: 700
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.5
                            }

                            function resumeSpin() {
                                bounceBackAnim.stop();
                                let cur = cdContainer.cdRotation % 360;
                                if (cur < 0) cur += 360;
                                cdContainer.cdRotation = cur;
                                spinAnim.from = cur;
                                spinAnim.to = cur + 360;
                                spinAnim.restart();
                            }

                            function stopSpin() {
                                spinAnim.stop();
                                let cur = cdContainer.cdRotation % 360;
                                if (cur < 0) cur += 360;
                                bounceBackAnim.from = cur;
                                bounceBackAnim.to = cur > 180 ? 360 : 0;
                                bounceBackAnim.restart();
                            }

                            Connections {
                                target: content
                                function onIsPlayingChanged() {
                                    if (content.isPlaying)
                                        cdContainer.resumeSpin();
                                    else
                                        cdContainer.stopSpin();
                                }
                            }

                            Component.onCompleted: {
                                if (content.isPlaying)
                                    cdContainer.resumeSpin();
                            }

                            ClippingRectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: Colors.surface
                                clip: true

                                Image {
                                    id: discArt
                                    anchors.fill: parent
                                    source: content.artwork
                                    sourceSize: Qt.size(128, 128)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                }

                                // Dim only when nothing is playing
                                Rectangle {
                                    anchors.fill: parent
                                    color: Qt.rgba(0, 0, 0, 0.35)
                                    visible: !content.hasActivePlayer
                                }
                            }
                        }
                    }
                }

                // ── Right: metadata + controls ──
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 3

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: content.hasActivePlayer ? root.getPlayerIcon(MprisController.activePlayer) : Icons.player
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: "#ffffff"
                        opacity: content.hasActivePlayer ? 1.0 : 0.5
                        layer.enabled: true
                        layer.effect: BgShadow {}
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -5
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MprisController.cyclePlayer(1)
                        }
                    }

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

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: content.hasActivePlayer
                              ? content.formatTime(content.position) + " / " + content.formatTime(content.length)
                              : "--:-- / --:--"
                        color: Qt.rgba(1, 1, 1, 0.75)
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-3)
                        layer.enabled: true
                        layer.effect: BgShadow {}
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        Text {
                            text: Icons.previous
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: MprisController.canGoPrevious ? "#ffffff" : Qt.rgba(1, 1, 1, 0.4)
                            layer.enabled: true
                            layer.effect: BgShadow {}
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                enabled: MprisController.canGoPrevious
                                onClicked: MprisController.previous()
                            }
                        }

                        StyledRect {
                            id: playBtn
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: 15
                            variant: "primary"
                            opacity: content.hasActivePlayer ? 1.0 : 0.5

                            Text {
                                anchors.centerIn: parent
                                text: content.isPlaying ? Icons.pause : Icons.play
                                font.family: Icons.font
                                font.pixelSize: 16
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
                            font.pixelSize: 16
                            color: MprisController.canGoNext ? "#ffffff" : Qt.rgba(1, 1, 1, 0.4)
                            layer.enabled: true
                            layer.effect: BgShadow {}
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                enabled: MprisController.canGoNext
                                onClicked: MprisController.next()
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10

                        Text {
                            text: Icons.shuffle
                            font.family: Icons.font
                            font.pixelSize: 12
                            color: MprisController.hasShuffle ? "#ffffff" : Qt.rgba(1, 1, 1, 0.5)
                            opacity: MprisController.shuffleSupported ? 1.0 : 0.35
                            layer.enabled: true
                            layer.effect: BgShadow {}
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                enabled: MprisController.shuffleSupported
                                onClicked: {
                                    if (MprisController.hasShuffle) {
                                        MprisController.setShuffle(false);
                                        MprisController.setLoopState(MprisLoopState.Playlist);
                                    } else {
                                        MprisController.setShuffle(true);
                                    }
                                }
                            }
                        }

                        Text {
                            text: MprisController.loopState === MprisLoopState.Track ? Icons.repeatOnce
                                : MprisController.loopState === MprisLoopState.Playlist ? Icons.repeat
                                : Icons.repeat
                            font.family: Icons.font
                            font.pixelSize: 12
                            color: MprisController.loopState !== MprisLoopState.None ? "#ffffff" : Qt.rgba(1, 1, 1, 0.5)
                            opacity: MprisController.loopSupported ? 1.0 : 0.35
                            layer.enabled: true
                            layer.effect: BgShadow {}
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                enabled: MprisController.loopSupported
                                onClicked: {
                                    if (MprisController.loopState === MprisLoopState.Playlist)
                                        MprisController.setLoopState(MprisLoopState.Track);
                                    else if (MprisController.loopState === MprisLoopState.Track)
                                        MprisController.setLoopState(MprisLoopState.None);
                                    else
                                        MprisController.setLoopState(MprisLoopState.Playlist);
                                }
                            }
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
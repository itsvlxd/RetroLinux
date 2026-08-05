import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.config

PanelWindow {
    id: root

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: Qt.rgba(0, 0, 0, 0.5)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    visible: GlobalStates.countdownOverlayVisible
    exclusionMode: ExclusionMode.Ignore

    property int secondsLeft: 0
    property bool previewActive: false

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.secondsLeft > 1) {
                root.secondsLeft--
            } else {
                countdownTimer.stop()
                root.secondsLeft = 0
                captureTimer.start()
            }
        }
    }

    Timer {
        id: captureTimer
        interval: 150
        onTriggered: {
            if (GlobalStates.countdownMode === "screenshot") {
                var mode = GlobalStates.pendingScreenshotMode
                if (mode === "screen") {
                    Screenshot.processMonitorScreen(GlobalStates.pendingScreenshotScreen)
                } else if (mode === "region") {
                    Screenshot.processRegion(Screenshot.selectionX, Screenshot.selectionY,
                        Screenshot.selectionW, Screenshot.selectionH)
                } else {
                    Screenshot.processFullscreen()
                }
                GlobalStates.pendingScreenshotMode = ""
            }
            GlobalStates.countdownMode = ""
            GlobalStates.countdownOverlayVisible = false
        }
    }

    Timer {
        id: previewTimer
        interval: 700
        onTriggered: {
            root.previewActive = false
            root.secondsLeft = GlobalStates.countdownMode === "screenshot"
                ? Config.tools.screenshotCountdown
                : Config.tools.recordingCountdown
            countdownTimer.start()
        }
    }

    onVisibleChanged: {
        if (visible) {
            if (Config.tools.previewCountdown) {
                root.previewActive = true
                root.secondsLeft = 0
                previewTimer.start()
            } else {
                root.previewActive = false
                root.secondsLeft = GlobalStates.countdownMode === "screenshot"
                    ? Config.tools.screenshotCountdown
                    : Config.tools.recordingCountdown
                countdownTimer.start()
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 240
        height: 240
        color: "transparent"

        Text {
            id: countdownText
            anchors.centerIn: parent
            font.bold: true
            color: "#ffffff"
            opacity: 0.95
            horizontalAlignment: Text.AlignHCenter

            text: {
                if (root.previewActive) {
                    return GlobalStates.countdownMode === "screenshot" ? Icons.camera : Icons.recordScreen
                }
                if (root.secondsLeft > 0)
                    return String(root.secondsLeft)
                return ""
            }

            font.family: root.previewActive ? Icons.font
                : (root.secondsLeft > 0 ? Styling.defaultFont : Icons.font)

            font.pixelSize: root.previewActive ? 72 : 128
        }
    }
}

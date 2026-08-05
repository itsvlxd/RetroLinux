pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.modules.components
import qs.modules.corners
import qs.modules.theme
import qs.modules.globals
import qs.modules.widgets.dashboard.widgets
import qs.config

// Lock surface UI - shown on each screen when locked
WlSessionLockSurface {
    id: root

    property bool startAnim: false
    property bool authenticating: false
    property string errorMessage: ""
    property int failLockSecondsLeft: 0

    // Always transparent - blur background handles the visuals
    color: "transparent"

    // Wallpaper background con Blur integrado
    TintedWallpaper {
        id: wallpaperBackground
        anchors.fill: parent
        z: 1
        radius: 0
        tintEnabled: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.tintEnabled : false

        property string lockscreenFramePath: {
            if (!GlobalStates.wallpaperManager)
                return "";
            return GlobalStates.wallpaperManager.getLockscreenFramePath(GlobalStates.wallpaperManager.currentWallpaper);
        }

        source: lockscreenFramePath ? "file://" + lockscreenFramePath : ""

        // Animación de opacidad (visibilidad)
        opacity: startAnim ? 1 : 0
        visible: true

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 2
                easing.type: Easing.OutQuint
            }
        }

        // Efecto de Blur y Zoom mediante capa
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: startAnim ? 1 : 0
            blurMax: 64
        }

        // Zoom animation
        property real zoomScale: startAnim ? 1.25 : 1.0
        transform: Scale {
            origin.x: wallpaperBackground.width / 2
            origin.y: wallpaperBackground.height / 2
            xScale: wallpaperBackground.zoomScale
            yScale: wallpaperBackground.zoomScale
        }

        Behavior on zoomScale {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 2
                easing.type: Easing.OutExpo
            }
        }
    }

    // Screen capture background (fondo absoluto con zoom sincronizado)
    ScreencopyView {
        id: screencopyBackground
        anchors.fill: parent
        captureSource: root.screen
        live: false
        paintCursor: false
        visible: startAnim  // Visible solo cuando startAnim es true
        z: 0  // Capa más baja - fondo absoluto

        property real zoomScale: startAnim ? 1.25 : 1.0

        transform: Scale {
            origin.x: screencopyBackground.width / 2
            origin.y: screencopyBackground.height / 2
            xScale: screencopyBackground.zoomScale
            yScale: screencopyBackground.zoomScale
        }

        Behavior on zoomScale {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 2
                easing.type: Easing.OutExpo
            }
        }
    }

    // Overlay for dimming
    Rectangle {
        id: dimOverlay
        anchors.fill: parent
        color: "black"
        opacity: startAnim ? 0.25 : 0
        z: 3

        property real zoomScale: startAnim ? 1.1 : 1.0

        transform: Scale {
            origin.x: dimOverlay.width / 2
            origin.y: dimOverlay.height / 2
            xScale: dimOverlay.zoomScale
            yScale: dimOverlay.zoomScale
        }

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 2
                easing.type: Easing.OutQuint
            }
        }

        Behavior on zoomScale {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 2
                easing.type: Easing.OutExpo
            }
        }
    }

    // Clock
    Item {
        id: clockContainer
        z: 10
        readonly property string pos: Config.lockscreen.clockPosition
        visible: pos !== "hidden"
        readonly property bool isCorner: pos.indexOf("-") >= 0
        readonly property bool atLeft: pos === "left" || pos.indexOf("left") >= 0
        readonly property bool atRight: pos === "right" || pos.indexOf("right") >= 0
        readonly property bool atTop: pos === "top" || (isCorner && pos.indexOf("top") >= 0)
        readonly property bool atBottom: pos === "bottom" || (isCorner && pos.indexOf("bottom") >= 0)
        readonly property bool atHCenter: pos === "top" || pos === "bottom"
        readonly property bool atVCenter: pos === "left" || pos === "right"
        readonly property bool atCenter: pos === "center"
        readonly property real _stackOffset: 0

        readonly property string style: Config.lockscreen.clockStyle
        width: style === "split" ? clockRow.width : inlineClock.implicitWidth
        height: style === "stacked" ? hoursTextS.height + minutesTextS.height : (style === "split" ? hoursText.height + hoursText.height * 0.5 : inlineClock.implicitHeight)

        anchors {
            centerIn: atCenter ? parent : undefined
            left: (!atCenter && atLeft) ? parent.left : undefined
            right: (!atCenter && atRight) ? parent.right : undefined
            top: (!atCenter && atTop) ? parent.top : undefined
            bottom: (!atCenter && atBottom) ? parent.bottom : undefined
            horizontalCenter: (!atCenter && atHCenter) ? parent.horizontalCenter : undefined
            verticalCenter: (!atCenter && atVCenter) ? parent.verticalCenter : undefined
            leftMargin: (!atCenter && atLeft) ? (startAnim ? 32 : -(width + 64)) : 0
            rightMargin: (!atCenter && atRight) ? (startAnim ? 32 : -(width + 64)) : 0
            topMargin: (!atCenter && (atTop || atHCenter)) ? (startAnim ? 32 : -100) : 0
            bottomMargin: (!atCenter && (atBottom || atHCenter)) ? (startAnim ? 32 : -100) : 0
        }

        Behavior on anchors.leftMargin { enabled: Config.animDuration > 0 && atLeft; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.rightMargin { enabled: Config.animDuration > 0 && atRight; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.topMargin { enabled: Config.animDuration > 0 && (atTop || atHCenter); NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.bottomMargin { enabled: Config.animDuration > 0 && (atBottom || atHCenter); NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutQuad } }

        property date currentTime: new Date()
        property bool isSplit: style === "split"
        property bool isInline: style === "inline"
        property bool isStacked: style === "stacked"

        opacity: startAnim ? 1 : 0

        // ── Split style (HH MM offset, default) ──
        Row {
            id: clockRow
            spacing: 0
            anchors.top: parent.top
            visible: clockContainer.isSplit

            Text {
                id: hoursText
                text: Config.bar.use12hFormat ? (clockContainer.currentTime.getHours() % 12 || 12).toString() : Qt.formatTime(clockContainer.currentTime, "hh")
                font.family: Config.lockscreen.clockFont
                font.pixelSize: Config.lockscreen.clockFontSize
                color: Config.resolveColor(Config.lockscreen.clockColor)
                antialiasing: true
                opacity: startAnim ? 1 : 0
                property real slideOffset: startAnim ? 0 : -150
                transform: Translate { y: hoursText.slideOffset }
                layer.enabled: true; layer.effect: BgShadow {}
                Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
                Behavior on slideOffset { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
            }

            Text {
                id: minutesText
                text: Qt.formatTime(clockContainer.currentTime, "mm")
                font.family: Config.lockscreen.clockFont
                font.pixelSize: Config.lockscreen.clockFontSize
                color: Config.resolveColor(Config.lockscreen.clockMinutesColor)
                antialiasing: true
                anchors.top: hoursText.top; anchors.topMargin: hoursText.height * 0.5
                opacity: startAnim ? 1 : 0
                property real slideOffset: startAnim ? 0 : 150
                transform: Translate { y: minutesText.slideOffset }
                layer.enabled: true; layer.effect: BgShadow {}
                Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
                Behavior on slideOffset { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
            }

            Text {
                id: amPmText
                text: Config.bar.use12hFormat ? Qt.formatTime(clockContainer.currentTime, "ap").toLowerCase() : ""
                font.family: Config.lockscreen.clockFont
                font.pixelSize: Config.lockscreen.clockFontSize * 0.42
                color: Config.resolveColor(Config.lockscreen.clockColor)
                antialiasing: true
                anchors.top: hoursText.top; anchors.topMargin: hoursText.height * 0.35
                visible: Config.bar.use12hFormat
                opacity: startAnim ? 1 : 0
                property real slideOffset: startAnim ? 0 : -150
                transform: Translate { y: amPmText.slideOffset }
                layer.enabled: true; layer.effect: BgShadow {}
                Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
                Behavior on slideOffset { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
            }
        }

        // ── Inline style (HH:MM single line) ──
        Text {
            id: inlineClock
            visible: clockContainer.isInline
            text: Qt.formatTime(clockContainer.currentTime, Config.bar.use12hFormat ? "h:mm ap" : "hh:mm")
            font.family: Config.lockscreen.clockFont
            font.pixelSize: Config.lockscreen.clockFontSize
            color: Config.resolveColor(Config.lockscreen.clockColor)
            antialiasing: true
            layer.enabled: true; layer.effect: BgShadow {}
        }

        // ── Stacked style (HH / MM separate centered lines) ──
        Column {
            anchors.centerIn: parent
            visible: clockContainer.isStacked
            spacing: -2

            Text {
                id: hoursTextS
                text: Config.bar.use12hFormat ? (clockContainer.currentTime.getHours() % 12 || 12).toString() : Qt.formatTime(clockContainer.currentTime, "hh")
                font.family: Config.lockscreen.clockFont
                font.pixelSize: Config.lockscreen.clockFontSize
                color: Config.resolveColor(Config.lockscreen.clockColor)
                antialiasing: true; anchors.horizontalCenter: parent.horizontalCenter
                layer.enabled: true; layer.effect: BgShadow {}
            }
            Text {
                id: minutesTextS
                text: Qt.formatTime(clockContainer.currentTime, "mm")
                font.family: Config.lockscreen.clockFont
                font.pixelSize: Config.lockscreen.clockFontSize * 0.7
                color: Config.resolveColor(Config.lockscreen.clockMinutesColor)
                antialiasing: true; anchors.horizontalCenter: parent.horizontalCenter
                layer.enabled: true; layer.effect: BgShadow {}
            }
        }

        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: clockContainer.currentTime = new Date()
        }
    }

    // Music player (slides from left)
    // Music player
    Item {
        id: playerContainer
        z: 10
        readonly property string pos: Config.lockscreen.musicPosition
        visible: pos !== "hidden"
        readonly property bool isCorner: pos.indexOf("-") >= 0
        readonly property bool atLeft: pos === "left" || pos.indexOf("left") >= 0
        readonly property bool atRight: pos === "right" || pos.indexOf("right") >= 0
        readonly property bool atTop: pos === "top" || (isCorner && pos.indexOf("top") >= 0)
        readonly property bool atBottom: pos === "bottom" || (isCorner && pos.indexOf("bottom") >= 0)
        readonly property bool atHCenter: pos === "top" || pos === "bottom"
        readonly property bool atVCenter: pos === "left" || pos === "right"

        readonly property real _stackOffset: {
            var off = 0;
            off += (pos === clockContainer.pos && clockContainer.visible) ? (clockContainer.height + 8) : 0;
            off += (pos === powerContainer.pos && powerContainer.visible) ? (powerContainer.height + 8) : 0;
            off += (pos === passwordContainer.pos && passwordContainer.visible) ? (passwordContainer.height + 8) : 0;
            off += (pos === weatherContainer.pos && weatherContainer.visible) ? (weatherContainer.height + 8) : 0;
            return off;
        }

        anchors {
            left: atLeft ? parent.left : undefined
            right: atRight ? parent.right : undefined
            top: atTop ? parent.top : undefined
            bottom: atBottom ? parent.bottom : undefined
            horizontalCenter: atHCenter ? parent.horizontalCenter : undefined
            verticalCenter: atVCenter ? parent.verticalCenter : undefined
            leftMargin: atLeft ? (startAnim ? 32 : -(width + 64)) : 0
            rightMargin: atRight ? (startAnim ? 32 : -(width + 64)) : 0
            topMargin: (atTop || atHCenter) ? (startAnim ? (32 + _stackOffset) : -100) : 0
            bottomMargin: (atBottom || atHCenter) ? (startAnim ? (32 + _stackOffset) : -100) : 0
        }
        width: 350
        height: playerContent.height

        opacity: startAnim ? 1 : 0

        Behavior on anchors.leftMargin { enabled: Config.animDuration > 0 && atLeft; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.rightMargin { enabled: Config.animDuration > 0 && !atLeft; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.topMargin { enabled: Config.animDuration > 0 && atTop; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.bottomMargin { enabled: Config.animDuration > 0 && !atTop; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutQuad } }

        LockPlayer {
            id: playerContent
            width: parent.width
        }
    }

    // Weather widget
    Item {
        id: weatherContainer
        z: 10
        readonly property string pos: Config.lockscreen.weatherPosition
        visible: pos !== "hidden"
        readonly property bool isCorner: pos.indexOf("-") >= 0
        readonly property bool atLeft: pos === "left" || pos.indexOf("left") >= 0
        readonly property bool atRight: pos === "right" || pos.indexOf("right") >= 0
        readonly property bool atTop: pos === "top" || (isCorner && pos.indexOf("top") >= 0)
        readonly property bool atBottom: pos === "bottom" || (isCorner && pos.indexOf("bottom") >= 0)
        readonly property bool atHCenter: pos === "top" || pos === "bottom"
        readonly property bool atVCenter: pos === "left" || pos === "right"

        readonly property real _stackOffset: {
            var off = 0;
            off += (pos === clockContainer.pos && clockContainer.visible) ? (clockContainer.height + 8) : 0;
            off += (pos === powerContainer.pos && powerContainer.visible) ? (powerContainer.height + 8) : 0;
            off += (pos === passwordContainer.pos && passwordContainer.visible) ? (passwordContainer.height + 8) : 0;
            return off;
        }

        anchors {
            left: atLeft ? parent.left : undefined
            right: atRight ? parent.right : undefined
            top: atTop ? parent.top : undefined
            bottom: atBottom ? parent.bottom : undefined
            horizontalCenter: atHCenter ? parent.horizontalCenter : undefined
            verticalCenter: atVCenter ? parent.verticalCenter : undefined
            leftMargin: atLeft ? (startAnim ? 32 : -(width + 64)) : 0
            rightMargin: atRight ? (startAnim ? 32 : -(width + 64)) : 0
            topMargin: (atTop || atHCenter) ? (startAnim ? (32 + _stackOffset) : -100) : 0
            bottomMargin: (atBottom || atHCenter) ? (startAnim ? (32 + _stackOffset) : -100) : 0
        }
        width: 350
        height: weatherContent.height

        opacity: startAnim ? 1 : 0

        Behavior on anchors.leftMargin { enabled: Config.animDuration > 0 && atLeft; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.rightMargin { enabled: Config.animDuration > 0 && !atLeft; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.topMargin { enabled: Config.animDuration > 0 && atTop; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.bottomMargin { enabled: Config.animDuration > 0 && !atTop; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutQuad } }

        LockWeather {
            id: weatherContent
            width: parent.width
        }
    }

    // Power menu
    Item {
        id: powerContainer
        z: 10
        readonly property string pos: Config.lockscreen.powerPosition
        visible: pos !== "hidden"
        readonly property bool isCorner: pos.indexOf("-") >= 0
        readonly property bool atLeft: pos === "left" || pos.indexOf("left") >= 0
        readonly property bool atRight: pos === "right" || pos.indexOf("right") >= 0
        readonly property bool atTop: pos === "top" || (isCorner && pos.indexOf("top") >= 0)
        readonly property bool atBottom: pos === "bottom" || (isCorner && pos.indexOf("bottom") >= 0)
        readonly property bool atHCenter: pos === "top" || pos === "bottom"
        readonly property bool atVCenter: pos === "left" || pos === "right"

        readonly property real _stackOffset: {
            return (pos === clockContainer.pos && clockContainer.visible) ? (clockContainer.height + 8) : 0;
        }

        anchors {
            left: atLeft ? parent.left : undefined
            right: atRight ? parent.right : undefined
            top: atTop ? parent.top : undefined
            bottom: atBottom ? parent.bottom : undefined
            horizontalCenter: atHCenter ? parent.horizontalCenter : undefined
            verticalCenter: atVCenter ? parent.verticalCenter : undefined
            leftMargin: atLeft ? (startAnim ? 32 : -(width + 64)) : 0
            rightMargin: atRight ? (startAnim ? 32 : -(width + 64)) : 0
            topMargin: (atTop || atHCenter) ? (startAnim ? 32 : -100) : 0
            bottomMargin: (atBottom || atHCenter) ? (startAnim ? 32 : -100) : 0
        }
        width: 208
        height: 56

        opacity: startAnim ? 1 : 0

        Behavior on anchors.leftMargin { enabled: Config.animDuration > 0 && atLeft; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.rightMargin { enabled: Config.animDuration > 0 && !atLeft; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.topMargin { enabled: Config.animDuration > 0 && atTop; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on anchors.bottomMargin { enabled: Config.animDuration > 0 && !atTop; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutExpo } }
        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutQuad } }

        StyledRect {
            id: pwrBg
            variant: "bg"
            anchors.fill: parent
            radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0

            RowLayout {
                anchors.centerIn: parent
                spacing: 2

                Item { Layout.preferredWidth: 44; Layout.preferredHeight: 44
                    Rectangle { anchors.centerIn: parent; width: 36; height: 36; radius: 18
                        color: ph1.containsMouse ? Styling.srItem("primary") : "transparent"
                        Text { anchors.centerIn: parent; text: Icons.suspend; font.family: Icons.font
                            font.pixelSize: 20; color: ph1.containsMouse ? Colors.overPrimary : Colors.overBackground }
                    }
                    MouseArea { id: ph1; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { actionProc.command = ["systemctl", "suspend"]; actionProc.running = true } }
                }

                Item { Layout.preferredWidth: 44; Layout.preferredHeight: 44
                    Rectangle { anchors.centerIn: parent; width: 36; height: 36; radius: 18
                        color: ph2.containsMouse ? Styling.srItem("primary") : "transparent"
                        Text { anchors.centerIn: parent; text: Icons.hibernate; font.family: Icons.font
                            font.pixelSize: 20; color: ph2.containsMouse ? Colors.overPrimary : Colors.overBackground }
                    }
                    MouseArea { id: ph2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { actionProc.command = ["systemctl", "hibernate"]; actionProc.running = true } }
                }

                Item { Layout.preferredWidth: 44; Layout.preferredHeight: 44
                    Rectangle { anchors.centerIn: parent; width: 36; height: 36; radius: 18
                        color: ph3.containsMouse ? Styling.srItem("primary") : "transparent"
                        Text { anchors.centerIn: parent; text: Icons.reboot; font.family: Icons.font
                            font.pixelSize: 20; color: ph3.containsMouse ? Colors.overPrimary : Colors.overBackground }
                    }
                    MouseArea { id: ph3; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { actionProc.command = ["systemctl", "reboot"]; actionProc.running = true } }
                }

                Item { Layout.preferredWidth: 44; Layout.preferredHeight: 44
                    Rectangle { anchors.centerIn: parent; width: 36; height: 36; radius: 18
                        color: ph4.containsMouse ? Colors.error : "transparent"
                        Text { anchors.centerIn: parent; text: Icons.shutdown; font.family: Icons.font
                            font.pixelSize: 20; color: ph4.containsMouse ? Colors.overError : Colors.overBackground }
                    }
                    MouseArea { id: ph4; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { actionProc.command = ["systemctl", "poweroff"]; actionProc.running = true } }
                }
            }
        }

        Process { id: actionProc; command: [] }
    }

    // Password input container
    Item {
        id: passwordContainer
        z: 10
        readonly property string pos: Config.lockscreen.passwordPosition
        visible: pos !== "hidden"
        readonly property bool isCorner: pos.indexOf("-") >= 0
        readonly property bool atLeft: pos === "left" || pos.indexOf("left") >= 0
        readonly property bool atRight: pos === "right" || pos.indexOf("right") >= 0
        readonly property bool atTop: pos === "top" || pos.indexOf("top") >= 0 && isCorner
        readonly property bool atBottom: pos === "bottom" || pos.indexOf("bottom") >= 0 && isCorner
        readonly property bool atHCenter: pos === "top" || pos === "bottom"
        readonly property bool atVCenter: pos === "left" || pos === "right"

        readonly property real _stackOffset: {
            var off = 0;
            off += (pos === clockContainer.pos && clockContainer.visible) ? (clockContainer.height + 8) : 0;
            off += (pos === powerContainer.pos && powerContainer.visible) ? (powerContainer.height + 8) : 0;
            return off;
        }

        anchors {
            left: atLeft ? parent.left : undefined
            right: atRight ? parent.right : undefined
            top: atTop ? parent.top : undefined
            bottom: atBottom ? parent.bottom : undefined
            horizontalCenter: atHCenter ? parent.horizontalCenter : undefined
            verticalCenter: atVCenter ? parent.verticalCenter : undefined
            leftMargin: atLeft ? (startAnim ? 32 : -(width + 64)) : 0
            rightMargin: atRight ? (startAnim ? 32 : -(width + 64)) : 0
            topMargin: (atTop || atHCenter) ? (startAnim ? (32 + _stackOffset) : -80) : 0
            bottomMargin: (atBottom || atHCenter) ? (startAnim ? (32 + _stackOffset) : -80) : 0
        }
        width: 350
        height: 96

        opacity: startAnim ? 1 : 0
        scale: startAnim ? 1 : 0.92

        Behavior on anchors.topMargin {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 2
                easing.type: Easing.OutExpo
            }
        }

        Behavior on anchors.bottomMargin {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 2
                easing.type: Easing.OutExpo
            }
        }

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 2
                easing.type: Easing.OutQuad
            }
        }

        Behavior on scale {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 2
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }
        }

        // Password input with avatar
        StyledRect {
            id: passwordInputBox
            variant: "bg"
            anchors.centerIn: parent
            width: parent.width
            height: 96
            radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0

            property real shakeOffset: 0
            property bool showError: false

            transform: Translate {
                x: passwordInputBox.shakeOffset
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 24
                spacing: 12

                // Avatar (64x64)
                Rectangle {
                    id: avatarContainer
                    width: 64
                    height: 64
                    radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0
                    color: "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        mipmap: true
                        id: userAvatar
                        anchors.fill: parent
                        source: `file://${Quickshell.env("HOME")}/.face.icon`
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                        visible: status === Image.Ready

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                            maskSource: ShaderEffectSource {
                                sourceItem: Rectangle {
                                    width: userAvatar.width
                                    height: userAvatar.height
                                    radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0
                                }
                            }
                        }
                    }

                    // Fallback icon if image not found
                    Text {
                        anchors.centerIn: parent
                        text: "👤"
                        font.pixelSize: 32
                        visible: userAvatar.status !== Image.Ready
                    }
                }

                // Password field
                StyledRect {
                    id: passwordFieldBg
                    width: parent.width - avatarContainer.width - parent.spacing
                    height: 48
                    anchors.verticalCenter: parent.verticalCenter
                    variant: passwordInputBox.showError ? "error" : "common"
                    radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 32
                        spacing: 8

                        // User icon / Spinner
                        Text {
                            id: userIcon
                            text: authenticating ? Icons.circleNotch : Icons.user
                            font.family: Icons.font
                            font.pixelSize: 24
                            color: passwordFieldBg.item
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            z: 10
                            rotation: 0

                            Behavior on color {
                                enabled: Config.animDuration > 0
                                ColorAnimation {
                                    duration: Config.animDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Timer {
                                id: spinnerTimer
                                interval: 100
                                repeat: true
                                running: authenticating
                                onTriggered: {
                                    userIcon.rotation = (userIcon.rotation + 45) % 360;
                                }
                            }

                            onTextChanged: {
                                if (userIcon.text === Icons.user) {
                                    userIcon.rotation = 0;
                                }
                            }
                        }

                        // Text field
                        TextField {
                            id: passwordInput
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            placeholderText: usernameCollector.text.trim()
                            placeholderTextColor: Qt.rgba(passwordFieldBg.item.r, passwordFieldBg.item.g, passwordFieldBg.item.b, 0.5)
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: passwordFieldBg.item
                            background: null
                            echoMode: TextInput.Password
                            verticalAlignment: TextInput.AlignVCenter
                            enabled: !authenticating

                            Behavior on color {
                                enabled: Config.animDuration > 0
                                ColorAnimation {
                                    duration: Config.animDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Behavior on placeholderTextColor {
                                enabled: Config.animDuration > 0
                                ColorAnimation {
                                    duration: Config.animDuration
                                    easing.type: Easing.OutQuad
                                }
                            }

                            onAccepted: {
                                if (passwordInput.text.trim() === "")
                                    return;

                                // Guardar contraseña y limpiar campo inmediatamente
                                authPasswordHolder.password = passwordInput.text;
                                passwordInput.text = "";

                                authenticating = true;
                                errorMessage = "";
                                pamAuth.start();
                            }
                        }
                    }
                }
            }

            SequentialAnimation {
                id: wrongPasswordAnim
                ScriptAction {
                    script: {
                        passwordInputBox.showError = true;
                    }
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: 10
                    duration: 50
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: -10
                    duration: 100
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: 10
                    duration: 100
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: 0
                    duration: 50
                    easing.type: Easing.InOutQuad
                }
                ScriptAction {
                    script: {
                        passwordInput.text = "";
                        authenticating = false;
                        passwordInputBox.showError = false;
                    }
                }
            }
        }
    }

    // Timer to unlock after exit animation
    Timer {
        id: unlockTimer
        interval: Config.animDuration * 2  // Wait for zoom out (1x) + fade out (1x)
        onTriggered: {
            GlobalStates.lockscreenVisible = false;
        }
    }

    // Processes for user info
    Process {
        id: usernameProc
        command: ["whoami"]
        running: true

        stdout: StdioCollector {
            id: usernameCollector
            waitForEnd: true
        }
    }

    Process {
        id: hostnameProc
        command: ["hostname"]
        running: true

        stdout: StdioCollector {
            id: hostnameCollector
            waitForEnd: true
        }
    }

    // Holder temporal para la contraseña durante autenticación
    QtObject {
        id: authPasswordHolder
        property string password: ""
    }

    // Proceso para verificar tiempo de faillock
    Process {
        id: failLockCheck
        command: ["bash", "-c", `faillock --user '${usernameCollector.text.trim()}' 2>/dev/null | grep -oP 'left \\K[0-9]+' | head -1`]
        running: false

        stdout: StdioCollector {
            id: failLockCollector

            onStreamFinished: {
                const output = text.trim();
                const seconds = parseInt(output);

                if (!isNaN(seconds) && seconds > 0) {
                    failLockSecondsLeft = seconds;
                    failLockCountdown.start();
                } else {
                    failLockSecondsLeft = 0;
                }
            }
        }
    }

    // Timer para actualizar el countdown de faillock
    Timer {
        id: failLockCountdown
        interval: 1000
        repeat: true
        running: false

        onTriggered: {
            if (failLockSecondsLeft > 0) {
                failLockSecondsLeft--;
            } else {
                stop();
                errorMessage = "";
            }
        }
    }

    // PAM authentication process
    PamContext {
        id: pamAuth
        // Use custom PAM config for lockscreen authentication
        configDirectory: Qt.resolvedUrl("../../config/pam").toString().replace("file://", "")
        config: "password.conf"

        onPamMessage: {
            console.log("PAM Message:", this.message, "Type:", this.messageType, "Required:", this.responseRequired);
            if (this.responseRequired) {
                // pam_unix asks for password, respond with stored password
                this.respond(authPasswordHolder.password);
            }
        }

        onCompleted: result => {
            // Limpiar contraseña
            authPasswordHolder.password = "";

            if (result === PamResult.Success) {
                // Autenticación exitosa - trigger exit animation
                startAnim = false;

                // Wait for exit animation, then unlock
                unlockTimer.start();

                errorMessage = "";
                authenticating = false;
            } else {
                // Error de autenticación
                errorMessage = "Authentication failed";
                console.warn("PAM auth failed with result:", result);
                if (Config.animDuration > 0) {
                    wrongPasswordAnim.start();
                }
            }
        }
    }

    // Screen corners
    RoundCorner {
        id: topLeft
        size: Styling.radius(4)
        anchors.left: parent.left
        anchors.top: parent.top
        corner: RoundCorner.CornerEnum.TopLeft
        z: 100
    }

    RoundCorner {
        id: topRight
        size: Styling.radius(4)
        anchors.right: parent.right
        anchors.top: parent.top
        corner: RoundCorner.CornerEnum.TopRight
        z: 100
    }

    RoundCorner {
        id: bottomLeft
        size: Styling.radius(4)
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        corner: RoundCorner.CornerEnum.BottomLeft
        z: 100
    }

    RoundCorner {
        id: bottomRight
        size: Styling.radius(4)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        corner: RoundCorner.CornerEnum.BottomRight
        z: 100
    }

    // Initialize when component is created (when lock becomes active)
    Component.onCompleted: {
        // Capture screen immediately
        screencopyBackground.captureFrame();

        // Start animations
        startAnim = true;
        passwordInput.forceActiveFocus();
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.theme
import qs.config

// Network & Bandwidth Monitor card. Theme-aware. Accepts real-time streams via
// its properties; the widget wires it to NetworkMetrics/NetworkService.
// variant: "compact" (2x2 160x160), "wide" (2x4 320x160), "slim" (1x4 320x80).
Rectangle {
    id: root

    property string variant: "compact"
    property bool showBackground: true
    property string interfaceName: ""
    property string ssid: ""
    property bool isConnected: false
    property int wifiStrength: 0
    property bool wifiEnabled: false
    property real downloadMbps: 0
    property real uploadMbps: 0
    property string localIp: ""
    property string publicIp: ""
    property bool publicIpValid: false
    property bool hideIp: true
    property var downloadHistory: []
    property var uploadHistory: []

    signal toggleWifiRequested()

    // Session-only reveal (eye) toggling the mask regardless of the saved state.
    property bool revealed: false

    function maskIp(ip) {
        var parts = String(ip).split(".");
        if (parts.length !== 4) return ip;
        return parts[0] + "." + parts[1] + ".***.***";
    }

    readonly property string displayedPublicIp: {
        if (!root.publicIpValid || !root.publicIp) return "—";
        return (root.hideIp && !root.revealed) ? root.maskIp(root.publicIp) : root.publicIp;
    }

    function wifiIcon() {
        if (!root.isConnected) return Icons.wifiX;
        if (root.wifiStrength > 80) return Icons.wifiHigh;
        if (root.wifiStrength > 55) return Icons.wifiMedium;
        if (root.wifiStrength > 30) return Icons.wifiLow;
        return Icons.wifiNone;
    }

    function speedText(v) {
        return v.toFixed(1);
    }

    function copyIp(ip) {
        if (!ip) return;
        copyProc.command = ["sh", "-c", "printf '%s' '" + String(ip).replace(/'/g, "") + "' | wl-copy"];
        copyProc.running = true;
    }

    Process {
        id: copyProc
        running: false
    }

    // Draw a dual-line sparkline (magenta upload behind, cyan download on top).
    function paintSpark(canvas, color, arr, fillAlpha) {
        var ctx = canvas.getContext("2d");
        var w = canvas.width, h = canvas.height;
        var dh = root.downloadHistory, uh = root.uploadHistory;
        var maxN = Math.max(dh.length, uh.length, 2);
        var maxV = 1;
        for (var i = 0; i < dh.length; i++) maxV = Math.max(maxV, dh[i]);
        for (var j = 0; j < uh.length; j++) maxV = Math.max(maxV, uh[j]);
        var pad = 2;
        var cw = w - pad * 2, ch = h - pad * 2;

        function pts(arr2) {
            var p = [];
            for (var k = 0; k < arr2.length; k++)
                p.push({ x: pad + (k / (maxN - 1)) * cw, y: pad + ch - (arr2[k] / maxV) * ch });
            return p;
        }

        function stroke(p2) {
            if (p2.length < 2) return;
            ctx.strokeStyle = color;
            ctx.lineWidth = 2;
            ctx.lineJoin = "round";
            ctx.beginPath();
            ctx.moveTo(p2[0].x, p2[0].y);
            for (var m = 1; m < p2.length; m++) ctx.lineTo(p2[m].x, p2[m].y);
            ctx.stroke();
        }

        function fillUnder(p2) {
            if (p2.length < 2) return;
            var grad = ctx.createLinearGradient(0, 0, 0, h);
            grad.addColorStop(0, Qt.rgba(color.r, color.g, color.b, fillAlpha));
            grad.addColorStop(1, Qt.rgba(color.r, color.g, color.b, 0));
            ctx.fillStyle = grad;
            ctx.beginPath();
            ctx.moveTo(p2[0].x, h);
            for (var n = 0; n < p2.length; n++) ctx.lineTo(p2[n].x, p2[n].y);
            ctx.lineTo(p2[p2.length - 1].x, h);
            ctx.closePath();
            ctx.fill();
        }

        var upload = pts(uh), download = pts(dh);
        stroke(upload); fillUnder(upload);
        stroke(download); fillUnder(download);
    }

    radius: 20
    clip: true

    // Theme-aware card surface (hidden when hosted inside WidgetHost)
    Rectangle {
        anchors.fill: parent
        visible: root.showBackground
        radius: 20
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.surfaceContainer }
            GradientStop { position: 1.0; color: Colors.surfaceContainerLow }
        }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.variant === "mini" ? miniLayout
                       : root.variant === "slim" ? slimLayout
                       : root.variant === "wide" ? wideLayout
                       : compactLayout
    }

    // ── iOS-style toggle (shared) ──
    Component {
        id: toggleComp
        Item {
            id: toggle
            width: 34
            height: 20
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: root.wifiEnabled ? Colors.primary : Colors.outlineVariant
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Rectangle {
                id: knob
                width: 16
                height: 16
                radius: width / 2
                color: Colors.surfaceContainerLowest
                x: root.wifiEnabled ? parent.width - knob.width - 2 : 2
                anchors.verticalCenter: parent.verticalCenter
                Behavior on x {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleWifiRequested()
            }
        }
    }

    // ── 2x2 compact ──
    Component {
        id: compactLayout
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: root.wifiIcon()
                    font.family: Icons.font
                    font.pixelSize: 16
                    color: root.isConnected ? Colors.overBackground : Colors.outline
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: root.ssid.length > 0 ? root.ssid : (root.isConnected ? "Connected" : "Disconnected")
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.interfaceName
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }

                Loader { sourceComponent: toggleComp }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text { text: Icons.arrowDown; font.family: Icons.font; font.pixelSize: 11; color: Colors.primary }
                Text { text: root.speedText(root.downloadMbps); color: Colors.overBackground; font.family: Config.theme.font; font.pixelSize: 16; font.weight: Font.Bold }
                Text { text: "Mbps"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 9; Layout.alignment: Qt.AlignBaseline }
                Item { Layout.fillWidth: true }
                Text { text: Icons.arrowUp; font.family: Icons.font; font.pixelSize: 11; color: Colors.magenta }
                Text { text: root.speedText(root.uploadMbps); color: Colors.overBackground; font.family: Config.theme.font; font.pixelSize: 16; font.weight: Font.Bold }
                Text { text: "Mbps"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 9; Layout.alignment: Qt.AlignBaseline }
            }

            Canvas {
                id: compactSpark
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                antialiasing: true
                Connections {
                    target: root
                    function onDownloadHistoryChanged() { compactSpark.requestPaint(); }
                    function onUploadHistoryChanged() { compactSpark.requestPaint(); }
                }
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    root.paintSpark(compactSpark, Colors.magenta, root.uploadHistory, 0.10);
                    root.paintSpark(compactSpark, Colors.primary, root.downloadHistory, 0.16);
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                radius: 10
                color: Colors.surfaceContainerHigh

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 5

                    Text { text: "LAN"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 9 }
                    Text { text: root.localIp.length > 0 ? root.localIp : "—"; color: Colors.overBackground; font.family: Config.theme.monoFont; font.pixelSize: 10; elide: Text.ElideRight }
                    Text {
                        Layout.fillWidth: true
                        text: ""
                    }
                    Text {
                        text: Icons.copy; font.family: Icons.font; font.pixelSize: 12; color: Colors.outline
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.copyIp(root.localIp) }
                    }
                }
            }
        }
    }

    // ── 2x4 wide ──
    Component {
        id: wideLayout
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: root.wifiIcon()
                    font.family: Icons.font
                    font.pixelSize: 18
                    color: root.isConnected ? Colors.overBackground : Colors.outline
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: root.ssid.length > 0 ? root.ssid : (root.isConnected ? "Connected" : "Disconnected")
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.interfaceName
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                Item { Layout.fillWidth: true }

                Loader { sourceComponent: toggleComp }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text { text: Icons.arrowDown; font.family: Icons.font; font.pixelSize: 12; color: Colors.primary }
                Text { text: root.speedText(root.downloadMbps); color: Colors.overBackground; font.family: Config.theme.font; font.pixelSize: 21; font.weight: Font.Bold }
                Text { text: "Mbps"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 10; Layout.alignment: Qt.AlignBaseline }
                Item { Layout.fillWidth: true }
                Text { text: Icons.arrowUp; font.family: Icons.font; font.pixelSize: 12; color: Colors.magenta }
                Text { text: root.speedText(root.uploadMbps); color: Colors.overBackground; font.family: Config.theme.font; font.pixelSize: 21; font.weight: Font.Bold }
                Text { text: "Mbps"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 10; Layout.alignment: Qt.AlignBaseline }
            }

            Canvas {
                id: wideSpark
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                antialiasing: true
                Connections {
                    target: root
                    function onDownloadHistoryChanged() { wideSpark.requestPaint(); }
                    function onUploadHistoryChanged() { wideSpark.requestPaint(); }
                }
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    root.paintSpark(wideSpark, Colors.magenta, root.uploadHistory, 0.10);
                    root.paintSpark(wideSpark, Colors.primary, root.downloadHistory, 0.16);
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                radius: 10
                color: Colors.surfaceContainerHigh

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 6

                    Text { text: "LAN"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 9 }
                    Text { text: root.localIp.length > 0 ? root.localIp : "—"; color: Colors.overBackground; font.family: Config.theme.monoFont; font.pixelSize: 10; elide: Text.ElideRight }
                    Text { text: "·"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 9 }
                    Text { text: "WAN"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 9 }
                    Text { Layout.fillWidth: true; text: root.displayedPublicIp; color: Colors.overBackground; font.family: Config.theme.monoFont; font.pixelSize: 10; elide: Text.ElideRight }
                    Text {
                        text: Icons.xeyes; font.family: Icons.font; font.pixelSize: 12
                        color: (root.hideIp && !root.revealed) ? Colors.primary : Colors.outline
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.revealed = !root.revealed }
                    }
                    Text {
                        text: Icons.copy; font.family: Icons.font; font.pixelSize: 12; color: Colors.outline
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.copyIp(root.publicIpValid ? root.publicIp : root.localIp) }
                    }
                }
            }
        }
    }

    // ── 1x3 mini (240x80) ──
    Component {
        id: miniLayout
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: root.wifiIcon()
                    font.family: Icons.font
                    font.pixelSize: 14
                    color: root.isConnected ? Colors.overBackground : Colors.outline
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: root.ssid.length > 0 ? root.ssid : (root.isConnected ? "Connected" : "Disconnected")
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                Loader { sourceComponent: toggleComp }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text { text: Icons.arrowDown; font.family: Icons.font; font.pixelSize: 10; color: Colors.primary }
                Text { text: root.speedText(root.downloadMbps); color: Colors.overBackground; font.family: Config.theme.font; font.pixelSize: 13; font.weight: Font.Bold }
                Text { text: "Mbps"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 8; Layout.alignment: Qt.AlignBaseline }
                Text { text: "·"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 9 }
                Text { text: Icons.arrowUp; font.family: Icons.font; font.pixelSize: 10; color: Colors.magenta }
                Text { text: root.speedText(root.uploadMbps); color: Colors.overBackground; font.family: Config.theme.font; font.pixelSize: 13; font.weight: Font.Bold }
                Text { text: "Mbps"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 8; Layout.alignment: Qt.AlignBaseline }
            }
        }
    }

    // ── 1x4 slim ──
    Component {
        id: slimLayout
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: root.wifiIcon()
                    font.family: Icons.font
                    font.pixelSize: 16
                    color: root.isConnected ? Colors.overBackground : Colors.outline
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: root.ssid.length > 0 ? root.ssid : (root.isConnected ? "Connected" : "Disconnected")
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                Loader { sourceComponent: toggleComp }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text { text: Icons.arrowDown; font.family: Icons.font; font.pixelSize: 11; color: Colors.primary }
                Text { text: root.speedText(root.downloadMbps); color: Colors.overBackground; font.family: Config.theme.font; font.pixelSize: 15; font.weight: Font.Bold }
                Text { text: "Mbps"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 9; Layout.alignment: Qt.AlignBaseline }
                Text { text: "·"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 10 }
                Text { text: Icons.arrowUp; font.family: Icons.font; font.pixelSize: 11; color: Colors.magenta }
                Text { text: root.speedText(root.uploadMbps); color: Colors.overBackground; font.family: Config.theme.font; font.pixelSize: 15; font.weight: Font.Bold }
                Text { text: "Mbps"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: 9; Layout.alignment: Qt.AlignBaseline }

                Canvas {
                    id: slimSpark
                    Layout.fillWidth: true
                    Layout.minimumWidth: 60
                    Layout.preferredHeight: 28
                    antialiasing: true
                    Connections {
                        target: root
                        function onDownloadHistoryChanged() { slimSpark.requestPaint(); }
                        function onUploadHistoryChanged() { slimSpark.requestPaint(); }
                    }
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        root.paintSpark(slimSpark, Colors.magenta, root.uploadHistory, 0.10);
                        root.paintSpark(slimSpark, Colors.primary, root.downloadHistory, 0.16);
                    }
                }
            }
        }
    }
}
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.config

// System Monitor card — multi-series sparkline graph for CPU/GPU/RAM/Disk + temps.
Rectangle {
    id: root

    property bool showBackground: true

    // Live metrics
    property real cpuUsage: 0
    property int cpuTemp: -1
    property real gpuUsage: 0
    property int gpuTemp: -1
    property real ramUsage: 0
    property real diskUsage: 0
    property int diskTemp: -1

    // Usage history (0..1)
    property var cpuHistory: []
    property var gpuHistory: []
    property var ramHistory: []

    // Temp history (raw degrees)
    property var cpuTempHistory: []
    property var gpuTempHistory: []
    property var diskTempHistory: []

    // Visibility toggles
    property bool showCpu: true
    property bool showGpu: true
    property bool showRam: true
    property bool showDisk: false
    property bool showCpuTemp: true
    property bool showGpuTemp: true
    property bool showDiskTemp: false

    // Distinct graph colors per metric
    readonly property color cpuColor: "#FF6B6B"
    readonly property color gpuColor: "#C084FC"
    readonly property color ramColor: "#34D399"
    readonly property color diskColor: "#FBBF24"
    readonly property color cpuTempColor: "#FB923C"
    readonly property color gpuTempColor: "#F472B6"
    readonly property color diskTempColor: "#A78BFA"

    radius: 20
    clip: true

    Rectangle {
        anchors.fill: parent
        visible: root.showBackground
        radius: 20
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.surfaceContainer }
            GradientStop { position: 1.0; color: Colors.surfaceContainerLow }
        }
    }

    function paintSeries(ctx, canvas, arr, color, fillAlpha, maxN, maxV) {
        if (!arr || arr.length < 2) return;
        var w = canvas.width, h = canvas.height;
        var pad = 2;
        var cw = w - pad * 2, ch = h - pad * 2;

        var pts = [];
        for (var k = 0; k < arr.length; k++) {
            pts.push({
                x: pad + (k / (maxN - 1)) * cw,
                y: pad + ch - (Math.min(arr[k], maxV) / maxV) * ch
            });
        }

        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.lineJoin = "round";
        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (var m = 1; m < pts.length; m++) ctx.lineTo(pts[m].x, pts[m].y);
        ctx.stroke();

        var grad = ctx.createLinearGradient(0, 0, 0, h);
        grad.addColorStop(0, Qt.rgba(color.r, color.g, color.b, fillAlpha));
        grad.addColorStop(1, Qt.rgba(color.r, color.g, color.b, 0));
        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.moveTo(pts[0].x, h);
        for (var n = 0; n < pts.length; n++) ctx.lineTo(pts[n].x, pts[n].y);
        ctx.lineTo(pts[pts.length - 1].x, h);
        ctx.closePath();
        ctx.fill();
    }

    function paintTempSeries(ctx, canvas, arr, color, maxN, tempMax) {
        if (!arr || arr.length < 2) return;
        var w = canvas.width, h = canvas.height;
        var pad = 2;
        var cw = w - pad * 2, ch = h - pad * 2;

        ctx.strokeStyle = color;
        ctx.lineWidth = 1.5;
        ctx.setLineDash([4, 3]);
        ctx.lineJoin = "round";
        ctx.beginPath();
        var started = false;
        for (var k = 0; k < arr.length; k++) {
            if (arr[k] < 0) continue;
            var px = pad + (k / (maxN - 1)) * cw;
            var py = pad + ch - (Math.min(arr[k], tempMax) / tempMax) * ch;
            if (!started) { ctx.moveTo(px, py); started = true; }
            else ctx.lineTo(px, py);
        }
        ctx.stroke();
        ctx.setLineDash([]);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: Icons.circuitry
                font.family: Icons.font
                font.pixelSize: 14
                color: Colors.primary
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                Layout.fillWidth: true
                text: "System Monitor"
                color: Colors.primary
                font.family: Config.theme.font
                font.pixelSize: 12
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
        }

        Canvas {
            id: sparkCanvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            antialiasing: true

            Connections {
                target: root
                function onCpuHistoryChanged() { sparkCanvas.requestPaint(); }
                function onGpuHistoryChanged() { sparkCanvas.requestPaint(); }
                function onRamHistoryChanged() { sparkCanvas.requestPaint(); }
                function onCpuTempHistoryChanged() { sparkCanvas.requestPaint(); }
                function onGpuTempHistoryChanged() { sparkCanvas.requestPaint(); }
                function onDiskTempHistoryChanged() { sparkCanvas.requestPaint(); }
                function onShowCpuChanged() { sparkCanvas.requestPaint(); }
                function onShowGpuChanged() { sparkCanvas.requestPaint(); }
                function onShowRamChanged() { sparkCanvas.requestPaint(); }
                function onShowDiskChanged() { sparkCanvas.requestPaint(); }
                function onShowCpuTempChanged() { sparkCanvas.requestPaint(); }
                function onShowGpuTempChanged() { sparkCanvas.requestPaint(); }
                function onShowDiskTempChanged() { sparkCanvas.requestPaint(); }
            }

            onPaint: {
                var ctx = getContext("2d");
                var w = width, h = height;
                ctx.clearRect(0, 0, w, h);

                ctx.strokeStyle = Qt.rgba(Colors.outline.r, Colors.outline.g, Colors.outline.b, 0.15);
                ctx.lineWidth = 1;
                ctx.setLineDash([3, 3]);
                var pad = 2, cw = w - pad * 2, ch = h - pad * 2;
                for (var g = 1; g <= 3; g++) {
                    var gy = pad + ch * (1 - g * 0.25);
                    ctx.beginPath();
                    ctx.moveTo(pad, gy);
                    ctx.lineTo(pad + cw, gy);
                    ctx.stroke();
                }
                ctx.setLineDash([]);

                var maxN = 2;
                var maxV = 1;
                if (root.showCpu) {
                    for (var i = 0; i < root.cpuHistory.length; i++) maxV = Math.max(maxV, root.cpuHistory[i]);
                    maxN = Math.max(maxN, root.cpuHistory.length);
                }
                if (root.showGpu) {
                    for (var j = 0; j < root.gpuHistory.length; j++) maxV = Math.max(maxV, root.gpuHistory[j]);
                    maxN = Math.max(maxN, root.gpuHistory.length);
                }
                if (root.showRam) {
                    for (var k = 0; k < root.ramHistory.length; k++) maxV = Math.max(maxV, root.ramHistory[k]);
                    maxN = Math.max(maxN, root.ramHistory.length);
                }

                var tempMax = 100;
                if (root.showCpuTemp) maxN = Math.max(maxN, root.cpuTempHistory.length);
                if (root.showGpuTemp) maxN = Math.max(maxN, root.gpuTempHistory.length);
                if (root.showDiskTemp) maxN = Math.max(maxN, root.diskTempHistory.length);

                if (root.showRam) root.paintSeries(ctx, sparkCanvas, root.ramHistory, root.ramColor, 0.10, maxN, maxV);
                if (root.showGpu) root.paintSeries(ctx, sparkCanvas, root.gpuHistory, root.gpuColor, 0.12, maxN, maxV);
                if (root.showCpu) root.paintSeries(ctx, sparkCanvas, root.cpuHistory, root.cpuColor, 0.16, maxN, maxV);

                if (root.showCpuTemp) root.paintTempSeries(ctx, sparkCanvas, root.cpuTempHistory, root.cpuTempColor, maxN, tempMax);
                if (root.showGpuTemp) root.paintTempSeries(ctx, sparkCanvas, root.gpuTempHistory, root.gpuTempColor, maxN, tempMax);
                if (root.showDiskTemp) root.paintTempSeries(ctx, sparkCanvas, root.diskTempHistory, root.diskTempColor, maxN, tempMax);
            }
        }

        // Bottom legend
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                visible: root.showCpu
                spacing: 3
                Text { text: Icons.cpu; font.family: Icons.font; font.pixelSize: 10; color: root.cpuColor }
                Text {
                    text: Math.round(root.cpuUsage) + "%"
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
                Text {
                    visible: root.showCpuTemp && root.cpuTemp >= 0
                    text: root.cpuTemp + "°"
                    color: root.cpuTempColor
                    font.family: Config.theme.font
                    font.pixelSize: 9
                }
            }

            RowLayout {
                visible: root.showGpu
                spacing: 3
                Text { text: Icons.gpu; font.family: Icons.font; font.pixelSize: 10; color: root.gpuColor }
                Text {
                    text: Math.round(root.gpuUsage) + "%"
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
                Text {
                    visible: root.showGpuTemp && root.gpuTemp >= 0
                    text: root.gpuTemp + "°"
                    color: root.gpuTempColor
                    font.family: Config.theme.font
                    font.pixelSize: 9
                }
            }

            RowLayout {
                visible: root.showRam
                spacing: 3
                Text { text: Icons.ram; font.family: Icons.font; font.pixelSize: 10; color: root.ramColor }
                Text {
                    text: Math.round(root.ramUsage) + "%"
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }

            RowLayout {
                visible: root.showDisk
                spacing: 3
                Text { text: Icons.disk; font.family: Icons.font; font.pixelSize: 10; color: root.diskColor }
                Text {
                    text: Math.round(root.diskUsage) + "%"
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
                Text {
                    visible: root.showDiskTemp && root.diskTemp >= 0
                    text: root.diskTemp + "°"
                    color: root.diskTempColor
                    font.family: Config.theme.font
                    font.pixelSize: 9
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}

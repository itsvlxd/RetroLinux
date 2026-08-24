import QtQuick
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config
import qs.modules.widgets.desktop

// Desktop analog clock — 2x2 (160x160) with multiple faces switchable via a
// gear button. Faces: classic, numeric, roman, dots, minimal, sector.
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
        var faces = ["classic", "numeric", "roman", "dots", "minimal", "sector"];
        var labels = ["Classic", "Numeric", "Roman", "Dots", "Minimal", "Sector"];
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

            property int h: 0
            property int m: 0
            property int s: 0

            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    var now = new Date();
                    content.h = now.getHours() % 12;
                    content.m = now.getMinutes();
                    content.s = now.getSeconds();
                    clockCanvas.requestPaint();
                }
            }

            Connections {
                target: root
                function onFaceChanged() {
                    clockCanvas.requestPaint();
                }
                function onWidgetDataChanged() {
                    clockCanvas.requestPaint();
                }
            }

            Canvas {
                id: clockCanvas
                anchors.fill: parent
                antialiasing: true
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Component.onCompleted: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var w = width, h = height;
                    var cx = w / 2, cy = h / 2;
                    var R = Math.min(w, h) / 2 - 6;

                    // Face
                    ctx.beginPath();
                    ctx.arc(cx, cy, R, 0, Math.PI * 2);
                    ctx.fillStyle = Colors.surfaceContainerLow;
                    ctx.fill();
                    ctx.lineWidth = 1;
                    ctx.strokeStyle = Colors.surfaceVariant;
                    ctx.stroke();

                    var f = root.face;
                    if (f === "classic") content.drawTicks(ctx, cx, cy, R);
                    else if (f === "numeric") content.drawTextMarkers(ctx, cx, cy, R, false);
                    else if (f === "roman") content.drawTextMarkers(ctx, cx, cy, R, true);
                    else if (f === "dots") content.drawDots(ctx, cx, cy, R);
                    else if (f === "sector") content.drawSector(ctx, cx, cy, R);
                    // minimal = no markers

                    content.drawHands(ctx, cx, cy, R);

                    // Center cap
                    ctx.beginPath();
                    ctx.arc(cx, cy, 5, 0, Math.PI * 2);
                    ctx.fillStyle = Colors.primary;
                    ctx.fill();
                }
            }

            function drawTicks(ctx, cx, cy, R) {
                for (var i = 0; i < 12; i++) {
                    var a = i * 30 * Math.PI / 180;
                    var long = (i % 3 === 0);
                    var r1 = R - (long ? 4 : 2), r2 = R - (long ? 13 : 9);
                    ctx.beginPath();
                    ctx.moveTo(cx + r1 * Math.sin(a), cy - r1 * Math.cos(a));
                    ctx.lineTo(cx + r2 * Math.sin(a), cy - r2 * Math.cos(a));
                    ctx.strokeStyle = Colors.overSurfaceVariant;
                    ctx.lineWidth = long ? 2.5 : 1.5;
                    ctx.stroke();
                }
            }

            function drawTextMarkers(ctx, cx, cy, R, roman) {
                var labels = roman
                    ? ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
                    : ["12", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"];
                ctx.fillStyle = Colors.overSurfaceVariant;
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                ctx.font = "bold " + (roman ? R * 0.11 : R * 0.17) + "px " + Config.theme.font;
                for (var i = 0; i < 12; i++) {
                    var a = i * 30 * Math.PI / 180;
                    var r = R - (roman ? R * 0.2 : R * 0.19);
                    ctx.fillText(labels[i], cx + r * Math.sin(a), cy - r * Math.cos(a));
                }
            }

            function drawDots(ctx, cx, cy, R) {
                for (var i = 0; i < 12; i++) {
                    var a = i * 30 * Math.PI / 180;
                    var r = R - R * 0.12;
                    ctx.beginPath();
                    ctx.arc(cx + r * Math.sin(a), cy - r * Math.cos(a), (i % 3 === 0) ? 3.5 : 2, 0, Math.PI * 2);
                    ctx.fillStyle = Colors.overSurfaceVariant;
                    ctx.fill();
                }
            }

            function drawSector(ctx, cx, cy, R) {
                for (var i = 0; i < 12; i++) {
                    var a = i * 30 * Math.PI / 180;
                    var long = (i % 3 === 0);
                    var r1 = R - (long ? 2 : 3), r2 = R - (long ? R * 0.22 : R * 0.12);
                    ctx.beginPath();
                    ctx.moveTo(cx + r1 * Math.sin(a), cy - r1 * Math.cos(a));
                    ctx.lineTo(cx + r2 * Math.sin(a), cy - r2 * Math.cos(a));
                    ctx.strokeStyle = Colors.overSurfaceVariant;
                    ctx.lineWidth = long ? 7 : 2;
                    ctx.stroke();
                }
            }

            function drawHands(ctx, cx, cy, R) {
                ctx.lineCap = "round";
                var ha = (content.h + content.m / 60) * 30 * Math.PI / 180;
                ctx.strokeStyle = Colors.overBackground;
                ctx.lineWidth = 5;
                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.lineTo(cx + R * 0.5 * Math.sin(ha), cy - R * 0.5 * Math.cos(ha));
                ctx.stroke();

                var ma = (content.m + content.s / 60) * 6 * Math.PI / 180;
                ctx.strokeStyle = Colors.overBackground;
                ctx.lineWidth = 3;
                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.lineTo(cx + R * 0.72 * Math.sin(ma), cy - R * 0.72 * Math.cos(ma));
                ctx.stroke();

                var sa = content.s * 6 * Math.PI / 180;
                ctx.strokeStyle = Colors.primary;
                ctx.lineWidth = 2;
                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.lineTo(cx + R * 0.8 * Math.sin(sa), cy - R * 0.8 * Math.cos(sa));
                ctx.stroke();
            }

            // Settings gear (always visible)
            StyledRect {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 6
                width: 22
                height: 22
                radius: 11
                variant: gearHover.hovered ? "focus" : "common"
                z: 20

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
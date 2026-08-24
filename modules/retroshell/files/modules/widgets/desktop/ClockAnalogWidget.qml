import QtQuick
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config
import qs.modules.widgets.desktop

// Desktop analog clock — 2x2 (160x160) with multiple faces switchable via a
// gear button. Faces: classic, numeric, roman, dots, sector, minimal, skeleton,
// rings, bold, tall. Hands are drawn as tapered shapes with a counterweight.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    property string face: "classic"
    property string handStyle: "taper"
    signal faceSelected(string face)
    signal handStyleSelected(string handStyle)

    onWidgetDataChanged: {
        root.face = (root.widgetData && root.widgetData.face) ? root.widgetData.face : "classic";
        root.handStyle = (root.widgetData && root.widgetData.handStyle) ? root.widgetData.handStyle : "taper";
    }

    function setFace(f) {
        root.face = f;
        root.faceSelected(f);
    }

    function setHandStyle(h) {
        root.handStyle = h;
        root.handStyleSelected(h);
        clockCanvas.requestPaint();
    }

    function openFaceMenu() {
        var faces = ["classic", "numeric", "roman", "dots", "sector", "minimal", "skeleton", "rings", "bold", "tall", "track", "diamond", "bauhaus", "railway"];
        var labels = ["Classic", "Numeric", "Roman", "Dots", "Sector", "Minimal", "Skeleton", "Rings", "Bold", "Tall", "Track", "Diamond", "Bauhaus", "Railway"];
        var hands = ["taper", "classic", "thin"];
        var handLabels = ["Tapered", "Classic Lines", "Thin"];
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
        items.push({ isSeparator: true, text: "Hands" });
        for (var j = 0; j < hands.length; j++) {
            (function (h, l) {
                items.push({
                    text: (root.handStyle === h ? "✓ " : "") + l,
                    isSeparator: false,
                    onTriggered: function () { root.setHandStyle(h); }
                });
            })(hands[j], handLabels[j]);
        }
        Visibilities.contextMenu.openCustomMenu(items, 200, 32, "clock");
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
                    else if (f === "rings") content.drawRings(ctx, cx, cy, R);
                    else if (f === "bold") content.drawBold(ctx, cx, cy, R);
                    else if (f === "tall") content.drawTall(ctx, cx, cy, R);
                    else if (f === "track") content.drawTrack(ctx, cx, cy, R);
                    else if (f === "diamond") content.drawDiamond(ctx, cx, cy, R);
                    else if (f === "bauhaus") content.drawBauhaus(ctx, cx, cy, R);
                    else if (f === "railway") content.drawRailway(ctx, cx, cy, R);
                    // minimal / skeleton = no markers

                    content.drawHands(ctx, cx, cy, R);
                }
            }

            // Tapered hand drawn pointing up (12); rotate by the angle to place it.
            function drawTaperedHand(ctx, cx, cy, angleRad, length, baseWidth, tail, color) {
                ctx.save();
                ctx.translate(cx, cy);
                ctx.rotate(angleRad);
                ctx.beginPath();
                ctx.moveTo(-baseWidth / 2, tail);
                ctx.lineTo(-baseWidth * 0.3, 0);
                ctx.lineTo(0, -length);
                ctx.lineTo(baseWidth * 0.3, 0);
                ctx.lineTo(baseWidth / 2, tail);
                ctx.closePath();
                ctx.fillStyle = color;
                ctx.fill();
                ctx.restore();
            }

            function drawHands(ctx, cx, cy, R) {
                var hs = root.handStyle;
                if (hs === "classic") content.drawHandsClassic(ctx, cx, cy, R);
                else if (hs === "thin") content.drawHandsThin(ctx, cx, cy, R);
                else content.drawHandsTaper(ctx, cx, cy, R);
            }

            // Previous style: simple round line strokes from the center.
            function drawHandsClassic(ctx, cx, cy, R) {
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

                ctx.beginPath();
                ctx.arc(cx, cy, 4, 0, Math.PI * 2);
                ctx.fillStyle = Colors.primary;
                ctx.fill();
            }

            // Thin elegant lines.
            function drawHandsThin(ctx, cx, cy, R) {
                ctx.lineCap = "round";
                var ha = (content.h + content.m / 60) * 30 * Math.PI / 180;
                ctx.strokeStyle = Colors.overBackground;
                ctx.lineWidth = 3;
                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.lineTo(cx + R * 0.52 * Math.sin(ha), cy - R * 0.52 * Math.cos(ha));
                ctx.stroke();

                var ma = (content.m + content.s / 60) * 6 * Math.PI / 180;
                ctx.strokeStyle = Colors.overBackground;
                ctx.lineWidth = 2;
                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.lineTo(cx + R * 0.74 * Math.sin(ma), cy - R * 0.74 * Math.cos(ma));
                ctx.stroke();

                var sa = content.s * 6 * Math.PI / 180;
                ctx.strokeStyle = Colors.primary;
                ctx.lineWidth = 1.2;
                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.lineTo(cx + R * 0.82 * Math.sin(sa), cy - R * 0.82 * Math.cos(sa));
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(cx, cy, 3, 0, Math.PI * 2);
                ctx.fillStyle = Colors.primary;
                ctx.fill();
            }

            // Current style: tapered shapes with a counterweight tail.
            function drawHandsTaper(ctx, cx, cy, R) {
                var skeleton = root.face === "skeleton";
                var ha = (content.h + content.m / 60) * 30 * Math.PI / 180;
                content.drawTaperedHand(ctx, cx, cy, ha, R * (skeleton ? 0.58 : 0.5), skeleton ? 3 : 5, R * 0.06, Colors.overBackground);

                var ma = (content.m + content.s / 60) * 6 * Math.PI / 180;
                content.drawTaperedHand(ctx, cx, cy, ma, R * 0.76, skeleton ? 2 : 3.4, R * 0.11, Colors.overBackground);

                var sa = content.s * 6 * Math.PI / 180;
                content.drawTaperedHand(ctx, cx, cy, sa, R * 0.84, skeleton ? 1.2 : 1.6, R * 0.17, Colors.primary);

                // Cap: primary ring + inner dot
                ctx.beginPath();
                ctx.arc(cx, cy, skeleton ? 3 : 4.5, 0, Math.PI * 2);
                ctx.fillStyle = Colors.primary;
                ctx.fill();
                ctx.beginPath();
                ctx.arc(cx, cy, skeleton ? 1.2 : 1.8, 0, Math.PI * 2);
                ctx.fillStyle = Colors.surfaceContainerLow;
                ctx.fill();
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

            // Rings: hollow circles at each hour position.
            function drawRings(ctx, cx, cy, R) {
                for (var i = 0; i < 12; i++) {
                    var a = i * 30 * Math.PI / 180;
                    var r = R - R * 0.16;
                    var x = cx + r * Math.sin(a), y = cy - r * Math.cos(a);
                    ctx.beginPath();
                    ctx.arc(x, y, (i % 3 === 0) ? 3.6 : 2.4, 0, Math.PI * 2);
                    ctx.strokeStyle = Colors.overSurfaceVariant;
                    ctx.lineWidth = (i % 3 === 0) ? 2 : 1.2;
                    ctx.stroke();
                }
            }

            // Bold: chunky rectangular markers.
            function drawBold(ctx, cx, cy, R) {
                for (var i = 0; i < 12; i++) {
                    var a = i * 30 * Math.PI / 180;
                    var long = (i % 3 === 0);
                    var r1 = R - (long ? 2 : 3), r2 = R - (long ? R * 0.2 : R * 0.1);
                    ctx.beginPath();
                    ctx.moveTo(cx + r1 * Math.sin(a), cy - r1 * Math.cos(a));
                    ctx.lineTo(cx + r2 * Math.sin(a), cy - r2 * Math.cos(a));
                    ctx.strokeStyle = Colors.overSurfaceVariant;
                    ctx.lineWidth = long ? 8 : 2.5;
                    ctx.stroke();
                }
            }

            // Tall: single 12 dot, otherwise clean.
            function drawTall(ctx, cx, cy, R) {
                ctx.beginPath();
                ctx.arc(cx, cy - (R - R * 0.07), 2.5, 0, Math.PI * 2);
                ctx.fillStyle = Colors.overSurfaceVariant;
                ctx.fill();
            }

            // Track: inner ring with hour ticks radiating out to the edge.
            function drawTrack(ctx, cx, cy, R) {
                ctx.beginPath();
                ctx.arc(cx, cy, R * 0.86, 0, Math.PI * 2);
                ctx.strokeStyle = Colors.overSurfaceVariant;
                ctx.lineWidth = 1.5;
                ctx.stroke();
                for (var i = 0; i < 12; i++) {
                    var a = i * 30 * Math.PI / 180;
                    var long = (i % 3 === 0);
                    var r1 = R * 0.86, r2 = R - (long ? 2 : 5);
                    ctx.beginPath();
                    ctx.moveTo(cx + r1 * Math.sin(a), cy - r1 * Math.cos(a));
                    ctx.lineTo(cx + r2 * Math.sin(a), cy - r2 * Math.cos(a));
                    ctx.strokeStyle = Colors.overSurfaceVariant;
                    ctx.lineWidth = long ? 2.5 : 1.5;
                    ctx.stroke();
                }
            }

            // Diamond: rhombus markers pointing at each hour.
            function drawDiamond(ctx, cx, cy, R) {
                for (var i = 0; i < 12; i++) {
                    var a = i * 30 * Math.PI / 180;
                    var r = R - R * 0.14;
                    var x = cx + r * Math.sin(a), y = cy - r * Math.cos(a);
                    var s = (i % 3 === 0) ? 4.5 : 3;
                    ctx.save();
                    ctx.translate(x, y);
                    ctx.rotate(a);
                    ctx.beginPath();
                    ctx.moveTo(0, -s);
                    ctx.lineTo(s, 0);
                    ctx.lineTo(0, s);
                    ctx.lineTo(-s, 0);
                    ctx.closePath();
                    ctx.fillStyle = Colors.overSurfaceVariant;
                    ctx.fill();
                    ctx.restore();
                }
            }

            // Bauhaus: slim, modern radial lines.
            function drawBauhaus(ctx, cx, cy, R) {
                for (var i = 0; i < 12; i++) {
                    var a = i * 30 * Math.PI / 180;
                    var long = (i % 3 === 0);
                    var r1 = R - (long ? 4 : 3), r2 = R - (long ? R * 0.22 : R * 0.14);
                    ctx.beginPath();
                    ctx.moveTo(cx + r1 * Math.sin(a), cy - r1 * Math.cos(a));
                    ctx.lineTo(cx + r2 * Math.sin(a), cy - r2 * Math.cos(a));
                    ctx.strokeStyle = Colors.overSurfaceVariant;
                    ctx.lineWidth = long ? 3 : 1.5;
                    ctx.stroke();
                }
            }

            // Railway: big block numerals at 12/3/6/9 + minute ticks.
            function drawRailway(ctx, cx, cy, R) {
                for (var j = 0; j < 60; j++) {
                    var t = j * 6 * Math.PI / 180;
                    var long = (j % 5 === 0);
                    var r1 = R - (long ? 6 : 3), r2 = R - (long ? 13 : 8);
                    ctx.beginPath();
                    ctx.moveTo(cx + r1 * Math.sin(t), cy - r1 * Math.cos(t));
                    ctx.lineTo(cx + r2 * Math.sin(t), cy - r2 * Math.cos(t));
                    ctx.strokeStyle = Colors.overSurfaceVariant;
                    ctx.lineWidth = long ? 2 : 1;
                    ctx.stroke();
                }
                ctx.fillStyle = Colors.overSurfaceVariant;
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                ctx.font = "bold " + (R * 0.28) + "px " + Config.theme.font;
                var labels = ["12", "3", "6", "9"];
                for (var i = 0; i < 4; i++) {
                    var a = i * 90 * Math.PI / 180;
                    var r = R * 0.68;
                    ctx.fillText(labels[i], cx + r * Math.sin(a), cy - r * Math.cos(a));
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
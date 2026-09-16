pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import qs.config

Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true

    // "arch" = progress ring around the icon, "bar" = small bar beneath it
    readonly property string batteryStyle: Config.bar?.batteryStyle ?? "arch"

    property color batteryColor: Colors.overBackground

    function refreshBatteryColor() {
        root.batteryColor = getBatteryColor();
    }

    // TEMPORARY: set to false to preview desktop mode (no battery)

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    // Popup visibility state
    property bool popupOpen: batteryPopup.isOpen
    onPopupOpenChanged: {
        if (popupOpen && !Battery.isPluggedIn) {
            var rd = Quickshell.env("RETRO_DIR");
            usageProc.command = ["bash", rd + "/scripts/battery_core.sh", "--usage", "10"];
            usageProc.running = true;
        }
        if (popupOpen && Battery.available) {
            batteryInfoProc.command = ["bash", "-c",
                "BAT=$(find /sys/class/power_supply/BAT* -maxdepth 0 2>/dev/null | head -1);" +
                "cat \"$BAT/cycle_count\" 2>/dev/null || echo 0;" +
                "cat \"$BAT/energy_full_design\" 2>/dev/null || echo 0;" +
                "cat \"$BAT/energy_full\" 2>/dev/null || echo 0;" +
                "cat \"$BAT/power_now\" 2>/dev/null || cat \"$BAT/current_now\" 2>/dev/null || echo 0"];
            batteryInfoProc.running = true;
        }
        if (popupOpen && !Battery.available) {
            var rd = Quickshell.env("RETRO_DIR");
            sysInfoProc.command = ["python3", rd + "/modules/retroshell/files/scripts/system_monitor.py", "3000", "/"];
            sysInfoProc.running = true;
        } else {
            sysInfoProc.running = false;
        }
    }

    property string sysCpuModel: ""
    property real sysCpuUsage: 0
    property int sysCpuTemp: -1
    property var sysGpuNames: []
    property real sysGpuUsage: 0
    property int sysGpuTemp: -1
    property real sysRamUsage: 0
    property real sysRamTotal: 0
    property real sysRamUsed: 0

    Process { id: sysInfoProc; running: false
        stdout: SplitParser {
            onRead: data => {
                var stats = JSON.parse(data);
                if (stats.static) {
                    sysCpuModel = stats.static.cpu_model || "";
                    sysGpuNames = stats.static.gpu_names || [];
                }
                if (stats.cpu) {
                    sysCpuUsage = stats.cpu.usage;
                    sysCpuTemp = stats.cpu.temp;
                }
                if (stats.ram) {
                    sysRamUsage = stats.ram.usage;
                    sysRamTotal = stats.ram.total;
                    sysRamUsed = stats.ram.used;
                }
                if (stats.gpu) {
                    sysGpuUsage = stats.gpu.usages ? stats.gpu.usages[0] || 0 : 0;
                    sysGpuTemp = stats.gpu.temps ? stats.gpu.temps[0] || -1 : -1;
                }
            }
        }
    }

    property var wattages: ({})
    property string powerSource: "AC"
    property bool isOnBattery: false
    property string usageText: ""
    property bool batteryCardHovered: false
    property bool saverToggle: false
    property int saverThreshold: 50
    property bool dimEnabled: false
    property int dimBrightness: 30
    property bool saverCardHovered: false
    property bool dimCardHovered: false

    property string batteryHealth: "N/A"
    property real batteryHealthPct: 0
    property int batteryCycles: 0
    property real batteryWatts: 0

    function getWattageText(profileName) {
        var retroProfile = profileName.replace("power-", "");
        var key = powerSource + "_" + retroProfile;
        var w = wattages[key];
        if (w !== undefined) return " · " + w + "W (" + powerSource.toUpperCase() + ")";
        return "";
    }

    Process {
        id: wattageProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n");
                var map = {};
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split(": ");
                    if (parts.length === 2) {
                        var key = parts[0].replace("PWR_", "").toLowerCase();
                        map[key] = parseInt(parts[1]);
                    }
                }
                wattages = map;
            }
        }
    }

    Process {
        id: sourceProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                isOnBattery = text.trim() === "true";
                powerSource = isOnBattery ? "bat" : "ac";
            }
        }
    }

    Process {
        id: usageProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n");
                if (lines.length < 2) return;
                var totalW = parseFloat(lines[0]).toFixed(1);
                var procs = [totalW + "W"];
                for (var i = 1; i < lines.length && i <= 5; i++) {
                    var parts = lines[i].split("|");
                    if (parts.length === 2) {
                        var cpu = Math.round(parseFloat(parts[0]));
                        var name = parts[1].substring(0, 25);
                        procs.push(cpu + "%  " + name);
                    }
                }
                usageText = procs.join("\n");
            }
        }
    }

    Process { id: saverReadProc; running: false
        stdout: StdioCollector {
            onStreamFinished: { saverToggle = text.trim() === "true"; }
        }
    }

    Process { id: saverSetProc; running: false; stdout: SplitParser {} }

    Process { id: thresholdReadProc; running: false
        stdout: StdioCollector {
            onStreamFinished: { var v = parseInt(text.trim()); if (!isNaN(v)) saverThreshold = v; }
        }
    }

    Process { id: thresholdSetProc; running: false; stdout: SplitParser {} }

    Process { id: dimReadProc; running: false
        stdout: StdioCollector {
            onStreamFinished: { dimEnabled = text.trim() === "true"; }
        }
    }

    Process { id: dimSetProc; running: false; stdout: SplitParser {} }

    Process { id: dimBrightnessReadProc; running: false
        stdout: StdioCollector {
            onStreamFinished: { var v = parseInt(text.trim()); if (!isNaN(v)) dimBrightness = v; }
        }
    }

    Process { id: dimBrightnessSetProc; running: false; stdout: SplitParser {} }

    Process {
        id: batteryInfoProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n");
                if (lines.length >= 4) {
                    var cycles = parseInt(lines[0]) || 0;
                    batteryCycles = cycles;
                    var eDesign = parseFloat(lines[1]) || 0;
                    var eFull = parseFloat(lines[2]) || 0;
                    batteryHealthPct = eDesign > 0 ? Math.round(eFull / eDesign * 100) : 0;
                    batteryHealth = batteryHealthPct + "%";
                    var pNow = parseFloat(lines[3]) || 0;
                    batteryWatts = parseFloat((pNow / 1000000).toFixed(1));
                }
            }
        }
    }

    Component.onCompleted: {
        var rd = Quickshell.env("RETRO_DIR");
        var cfg = Quickshell.env("RETRO_CONFIG") || Quickshell.env("HOME") + "/.config/retro";
        root.refreshBatteryColor();
        wattageProc.command = ["bash", rd + "/scripts/power_core.sh", "--list"];
        wattageProc.running = true;
        sourceProc.command = ["bash", rd + "/scripts/power_core.sh", "--source"];
        sourceProc.running = true;
        saverReadProc.command = ["bash", "-c", "source '" + cfg + "/variables.sh' 2>/dev/null; echo $BAT_SAVER_ON_PWR_DIS"];
        saverReadProc.running = true;
        thresholdReadProc.command = ["bash", "-c", "source '" + cfg + "/variables.sh' 2>/dev/null; echo $BAT_SAVER_THRESHOLD"];
        thresholdReadProc.running = true;
        dimReadProc.command = ["bash", "-c", "source '" + cfg + "/variables.sh' 2>/dev/null; echo $BAT_SAVER_BRIGHTNESS_DIM"];
        dimReadProc.running = true;
        dimBrightnessReadProc.command = ["bash", "-c", "source '" + cfg + "/variables.sh' 2>/dev/null; echo $BAT_SAVER_BRIGHTNESS"];
        dimBrightnessReadProc.running = true;
    }

    // Function to interpolate color between green and red based on battery percentage
    function getBatteryColor() {
        if (!Battery.available)
            return Colors.overBackground;

        const pct = Battery.percentage;
        if (pct <= 15)
            return Colors.red;
        if (pct >= 85)
            return Colors.green;

        // Linear interpolation between red (15%) and green (85%)
        const ratio = (pct - 15) / (85 - 15);
        return Qt.rgba(Colors.red.r + (Colors.green.r - Colors.red.r) * ratio, Colors.red.g + (Colors.green.g - Colors.red.g) * ratio, Colors.red.b + (Colors.green.b - Colors.red.b) * ratio, 1);
    }

    implicitWidth: 36
    implicitHeight: 36
    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    // Main button with circular progress
    StyledRect {
        id: buttonBg
        variant: root.popupOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled

        topLeftRadius: root.vertical ? root.startRadius : root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.vertical ? root.endRadius : root.endRadius

        // Background highlight on hover
        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.popupOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        // Circular progress indicator (only if battery available and arch style)
        Item {
            id: progressCanvas
            anchors.centerIn: parent
            width: 32
            height: 32
            visible: Battery.available && root.batteryStyle !== "bar"

            property real angle: (Battery.percentage / 100) * (360 - 2 * gapAngle)
            property real radius: 12
            property real lineWidth: 3
            property real gapAngle: 45

            Canvas {
                id: canvas
                anchors.fill: parent
                antialiasing: true

                onPaint: {
                    let ctx = getContext("2d");
                    ctx.reset();

                    let centerX = width / 2;
                    let centerY = height / 2;
                    let radius = progressCanvas.radius;
                    let lineWidth = progressCanvas.lineWidth;

                    ctx.lineCap = "round";

                    // Base start angle (matching CircularControl: bottom + gap)
                    let baseStartAngle = (Math.PI / 2) + (progressCanvas.gapAngle * Math.PI / 180);
                    let progressAngleRad = progressCanvas.angle * Math.PI / 180;

                    // Draw background track (remaining part)
                    let totalAngleRad = (360 - 2 * progressCanvas.gapAngle) * Math.PI / 180;

                    ctx.strokeStyle = Colors.outlineVariant;
                    ctx.lineWidth = lineWidth;
                    ctx.beginPath();
                    ctx.arc(centerX, centerY, radius, baseStartAngle + progressAngleRad, baseStartAngle + totalAngleRad, false);
                    ctx.stroke();

                    // Draw progress
                    if (progressCanvas.angle > 0) {
                        ctx.strokeStyle = root.getBatteryColor();
                        ctx.lineWidth = lineWidth;
                        ctx.beginPath();
                        ctx.arc(centerX, centerY, radius, baseStartAngle, baseStartAngle + progressAngleRad, false);
                        ctx.stroke();
                    }
                }

                Connections {
                    target: progressCanvas
                    function onAngleChanged() {
                        canvas.requestPaint();
                    }
                }

                Connections {
                    target: Battery
                    function onPercentageChanged() {
                        canvas.requestPaint();
                    }
                }
            }

            Behavior on angle {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Small progress bar under the icon (bar style)
        Item {
            id: miniBar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            width: 22
            height: 3
            visible: Battery.available && root.batteryStyle === "bar"
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Colors.outlineVariant
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * (Battery.percentage / 100)
                radius: height / 2
                color: root.batteryColor

                Behavior on width {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Central icon (plug for no-battery PCs, battery-charging/level otherwise)
        Text {
            id: batteryIcon
            anchors.centerIn: parent
            text: Battery.available ? Battery.getBatteryIcon(Config.bar?.batteryStyle === "bar") : Icons.plug
            font.family: Icons.font
            font.pixelSize: Battery.available ? 14 : 18
            color: root.popupOpen ? buttonBg.item : Colors.overBackground

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation {
                    duration: Config.animDuration / 2
                }
            }

            Connections {
                target: Battery
                function onIsPluggedInChanged() {
                    batteryIcon.text = Battery.available ? Battery.getBatteryIcon(Config.bar?.batteryStyle === "bar") : Icons.plug;
                    root.refreshBatteryColor();
                }
                function onPercentageChanged() {
                    batteryIcon.text = Battery.available ? Battery.getBatteryIcon(Config.bar?.batteryStyle === "bar") : Icons.plug;
                    root.refreshBatteryColor();
                    canvas.requestPaint();
                }
                function onAvailableChanged() {
                    batteryIcon.text = Battery.available ? Battery.getBatteryIcon(Config.bar?.batteryStyle === "bar") : Icons.plug;
                    root.refreshBatteryColor();
                }
            }

            Connections {
                target: Colors
                function onFileChanged() {
                    Qt.callLater(() => {
                        root.refreshBatteryColor();
                        canvas.requestPaint();
                    });
                }
                function onRedChanged() {
                    root.refreshBatteryColor();
                    canvas.requestPaint();
                }
                function onGreenChanged() {
                    root.refreshBatteryColor();
                    canvas.requestPaint();
                }
                function onOutlineVariantChanged() {
                    canvas.requestPaint();
                }
                function onOverBackgroundChanged() {
                    root.refreshBatteryColor();
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: batteryPopup.toggle()
        }

        StyledToolTip {
            visible: root.isHovered && !root.popupOpen
            tooltipText: Battery.available ? ("Battery: " + Math.round(Battery.percentage) + "%" + (Battery.isCharging ? " (Charging)" : "")) : ("Power Profile: " + PowerProfile.getProfileDisplayName(PowerProfile.currentProfile))
        }
    }

    // Battery popup with Power Profiles
    BarPopup {
        id: batteryPopup
        anchorItem: buttonBg
        bar: root.bar

        contentWidth: Math.max(300, mainColumn.implicitWidth + batteryPopup.popupPadding * 2)
        contentHeight: (Battery.available ? (64 + 4 + 50 + 4 + 64) : 64) + 36 + batteryPopup.popupPadding * 2

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            spacing: 4

            StyledRect {
                id: batteryDetailsContainer
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                visible: Battery.available
                variant: "common"
                enableShadow: false

                radius: Styling.radius(0)

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: {
                        batteryCardHovered = true;
                        if (!Battery.isPluggedIn) {
                            var rd = Quickshell.env("RETRO_DIR");
                            usageProc.command = ["bash", rd + "/scripts/battery_core.sh", "--usage", "10"];
                            usageProc.running = true;
                        }
                    }
                    onExited: batteryCardHovered = false
                }

                StyledToolTip {
                    show: batteryCardHovered && !Battery.isPluggedIn && usageText !== ""
                    tooltipText: usageText
                }

                Item {
                    anchors.fill: parent
                    clip: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: batteryDetailsContainer.height * Battery.percentage / 100
                        // color: root.getBatteryColor()  ← battery gradient
                        color: Styling.srItem("overprimary")
                        opacity: 0.65

                        Behavior on height {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: 400
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    WavyLine {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        y: batteryDetailsContainer.height * (100 - Battery.percentage) / 100 - height / 2
                        height: 16
                        // color: root.getBatteryColor()  ← battery gradient
                        color: Styling.srItem("overprimary")
                        lineWidth: 3
                        amplitudeMultiplier: 0.6
                        frequency: 3
                        running: true
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 12

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: Battery.getBatteryIcon(false)
                        font.family: Icons.font
                        font.pixelSize: 24
                        color: root.batteryColor

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var rd = Quickshell.env("RETRO_DIR");
                                saverSetProc.command = ["bash", "-c", "retro settings battery &"];
                                saverSetProc.running = true;
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: Battery.isPluggedIn ? (Battery.isCharging ? "Charging" : "Full") : "On battery"
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(0)
                            font.bold: true
                            color: Colors.overBackground
                        }

                        Text {
                            text: Battery.isPluggedIn ? (Battery.timeToFull !== "" ? "Full in " + Battery.timeToFull : "Fully charged") : (Battery.timeToEmpty !== "" ? Battery.timeToEmpty + " remaining" : "") + (!Battery.isPluggedIn && usageText ? " · " + usageText.split("\n")[0] : "")
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overBackground
                            opacity: 0.8
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    // Battery percentage display
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: Math.round(Battery.percentage) + "%"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(2)
                        font.bold: true
                        color: root.batteryColor
                        opacity: 0.8
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                spacing: 4
                visible: Battery.available

                Repeater {
                    model: [
                        { title: "Health",  value: batteryHealth },
                        { title: "Capacity", value: Math.round(Battery.percentage) + "%" },
                        { title: "Watts",   value: batteryWatts + "W" }
                    ]

                    delegate: StyledRect {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        variant: "common"
                        enableShadow: false
                        radius: Styling.radius(0)

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.title
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.primary
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.value
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(2)
                                font.bold: true
                                color: Colors.overBackground
                            }
                        }
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                visible: !Battery.available
                variant: "common"
                enableShadow: false
                radius: Styling.radius(0)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    spacing: 12

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "\uE562"
                        font.family: Icons.font
                        font.pixelSize: 24
                        color: Styling.srItem("overprimary")

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var rd = Quickshell.env("RETRO_DIR");
                                saverSetProc.command = ["bash", "-c", "retro settings power &"];
                                saverSetProc.running = true;
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Text {
                                id: cpuModelText
                                Layout.fillWidth: true
                                text: sysCpuModel || "CPU"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(0)
                                font.bold: true
                                color: sysCpuTemp >= 75 ? Colors.red : Colors.overBackground
                                elide: Text.ElideMiddle

                                property bool hovered: false

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: cpuModelText.hovered = true
                                    onExited: cpuModelText.hovered = false
                                }

                                StyledToolTip {
                                    show: cpuModelText.hovered
                                    tooltipText: "Temperature: " + (sysCpuTemp >= 0 ? sysCpuTemp + "°C" : "N/A")
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: Math.round(sysCpuUsage) + "%"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(2)
                                font.bold: true
                                color: Styling.srItem("overprimary")
                                opacity: 0.8
                            }
                        }

                        Text {
                            text: "GPU " + Math.round(sysGpuUsage) + "% · " + (sysGpuTemp >= 0 ? sysGpuTemp + "°C" : "N/A")
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overBackground
                            opacity: 0.8
                            visible: sysGpuTemp >= 0 || sysGpuUsage > 0
                        }

                        Text {
                            text: "RAM " + (sysRamUsed / 1048576).toFixed(1) + "/" + (sysRamTotal / 1048576).toFixed(1) + "GB (" + Math.round(sysRamUsage) + "%)"
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overBackground
                            opacity: 0.8
                        }
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                visible: Battery.available
                variant: "common"
                enableShadow: false
                radius: Styling.radius(0)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    spacing: 4

                    StyledSlider {
                        id: autoSaverSlider
                        Layout.fillWidth: true
                        height: 18
                        value: saverThreshold / 100.0
                        wavy: true
                        thickness: 3
                        handleSpacing: 0
                        iconClickable: true
                        iconPos: "start"
                        icon: "\uEB56"
                        progressColor: saverToggle ? Styling.srItem("overprimary") : Colors.outline
                        backgroundColor: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.2)
                        wavyAmplitude: 1.5 * value
                        wavyFrequency: 8.0 * value

                        onValueChanged: {
                            var v = Math.round(value * 100);
                            if (v !== saverThreshold) {
                                saverThreshold = v;
                                var rd = Quickshell.env("RETRO_DIR");
                                thresholdSetProc.command = ["bash", rd + "/scripts/battery_core.sh", "--saver", "" + v];
                                thresholdSetProc.running = true;
                            }
                        }

                        onIconClicked: {
                            saverToggle = !saverToggle;
                            var rd = Quickshell.env("RETRO_DIR");
                            var val = saverToggle ? "true" : "false";
                            saverSetProc.command = ["bash", "-c", "source '" + rd + "/lib/helpers.sh' 2>/dev/null; set_var BAT_SAVER_ON_PWR_DIS " + val];
                            saverSetProc.running = true;
                        }

                        Connections {
                            target: autoSaverSlider
                            function onIconHovered(h) { saverCardHovered = h; }
                        }
                    }

                    StyledSlider {
                        id: dimSlider
                        Layout.fillWidth: true
                        height: 18
                        value: dimBrightness / 100.0
                        wavy: true
                        thickness: 3
                        handleSpacing: 0
                        iconClickable: true; iconPos: "start"; icon: "󰃡"
                        progressColor: dimEnabled ? Styling.srItem("overprimary") : Colors.outline
                        backgroundColor: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.2)
                        wavyAmplitude: 1.5 * value
                        wavyFrequency: 8.0 * value

                        onValueChanged: {
                            var v = Math.round(value * 100);
                            if (v !== dimBrightness) {
                                dimBrightness = v;
                                var rd = Quickshell.env("RETRO_DIR");
                                dimBrightnessSetProc.command = ["bash", "-c", "source '" + rd + "/lib/helpers.sh' 2>/dev/null; set_var BAT_SAVER_BRIGHTNESS " + v];
                                dimBrightnessSetProc.running = true;
                            }
                        }

                        onIconClicked: {
                            dimEnabled = !dimEnabled;
                            var rd = Quickshell.env("RETRO_DIR");
                            var val = dimEnabled ? "true" : "false";
                            dimSetProc.command = ["bash", "-c", "source '" + rd + "/lib/helpers.sh' 2>/dev/null; set_var BAT_SAVER_BRIGHTNESS_DIM " + val];
                            dimSetProc.running = true;
                        }

                        Connections {
                            target: dimSlider
                            function onIconHovered(h) { dimCardHovered = h; }
                        }
                    }
                }
            }

            StyledToolTip {
                show: saverCardHovered
                tooltipText: "Battery Saver On Disconnect"
            }

            StyledToolTip {
                show: dimCardHovered
                tooltipText: "Dim Brightness On Saver"
            }

            RowLayout {

            RowLayout {
                id: profilesRow
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                Repeater {
                    model: PowerProfile.availableProfiles

                    delegate: StyledRect {
                        id: profileButton
                        required property string modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.preferredWidth: 80
                        height: 36

                        readonly property bool isSelected: PowerProfile.currentProfile === modelData
                        readonly property bool isFirst: index === 0
                        readonly property bool isLast: index === PowerProfile.availableProfiles.length - 1
                        property bool buttonHovered: false

                        readonly property real defaultRadius: Styling.radius(0)
                        readonly property real selectedRadius: Styling.radius(0) / 2

                        variant: isSelected ? "primary" : (buttonHovered ? "focus" : "common")
                        enableShadow: false

                        topLeftRadius: isFirst ? defaultRadius : selectedRadius
                        bottomLeftRadius: isFirst ? defaultRadius : selectedRadius
                        topRightRadius: isLast ? defaultRadius : selectedRadius
                        bottomRightRadius: isLast ? defaultRadius : selectedRadius

                        Text {
                            anchors.centerIn: parent
                            text: PowerProfile.getProfileIcon(profileButton.modelData)
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: profileButton.item
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onEntered: profileButton.buttonHovered = true
                            onExited: profileButton.buttonHovered = false

                            onClicked: {
                                PowerProfile.setProfile(profileButton.modelData);
                            }
                        }

                        StyledToolTip {
                            show: profileButton.buttonHovered
                            tooltipText: PowerProfile.getProfileDisplayName(profileButton.modelData) + getWattageText(profileButton.modelData)
                        }
                    }
                }
            }
        }
    }
}
}

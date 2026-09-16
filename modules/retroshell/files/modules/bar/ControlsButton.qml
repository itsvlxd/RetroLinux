pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.config

Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    // Popup visibility state (tracks intent, not animation)
    property bool popupOpen: controlsPopup.isOpen

    property string eqCurrent: ""
    property var eqProfiles: []
    property int eqIndex: 0

    property var sinkDevices: []
    property var sourceDevices: []
    property string currentSinkId: ""
    property string currentSourceId: ""
    property int sinkDeviceIndex: 0
    property int sourceDeviceIndex: 0

    property var appNodeBlacklist: [/speech[-_ ]?dummy/i, /speech[-_ ]?dispatcher/i]

    property bool priorityEnabled: true

    // Action button customization knobs (radii follow Config.roundness via Styling.radius)
    property real actionButtonHeight: 36
    property real actionButtonSpacing: 4
    property real actionRadiusOffset: 0
    property real actionIconSize: 18

    property var actionButtons: [
        {
            icon: root.priorityEnabled ? Icons.shieldCheck : Icons.shield,
            tooltip: "Device priority: " + (root.priorityEnabled ? "Enabled" : "Disabled"),
            isSelected: root.priorityEnabled,
            onClicked: function() {
                priorityToggleProc.command = ["retro", "audio", "priority", root.priorityEnabled ? "off" : "on"];
                priorityToggleProc.running = true;
                root.priorityEnabled = !root.priorityEnabled;
            }
        },
        {
            icon: Icons.arrowCounterClockwise,
            tooltip: "Restart EasyEffects",
            isSelected: false,
            onClicked: function() {
                eeRestartProc.command = ["retro", "audio", "ee", "restart"];
                eeRestartProc.running = true;
            }
        },
        {
            icon: Icons.popOpen,
            tooltip: "Open EasyEffects",
            isSelected: false,
            onClicked: function() {
                eeOpenProc.command = ["retro", "audio", "ee", "open"];
                eeOpenProc.running = true;
            }
        }
    ]

    function appIcon(name) {
        const n = (name || "").toLowerCase();
        if (n.includes("spotify")) return Icons.spotify;
        if (n.includes("chromium") || n.includes("chrome")) return Icons.chromium;
        if (n.includes("firefox")) return Icons.firefox;
        if (n.includes("telegram")) return Icons.telegram;
        if (n.includes("zen")) return Icons.globe;
        if (n.includes("webrtc voiceengine")) return Icons.discord;
        return "";
    }

    Process { id: eqCurrentProc; running: false
        stdout: StdioCollector { onStreamFinished: { eqCurrent = text.trim(); } }
    }

    Process { id: eqListProc; running: false
        stdout: StdioCollector { onStreamFinished: { eqProfiles = text.trim().split("\n").filter(function(l){return l.length>0});
            for (var i=0; i<eqProfiles.length; i++) { if (eqProfiles[i] === eqCurrent) { eqIndex = i; break; } }
        } }
    }

    Process { id: eqApplyProc; running: false; stdout: SplitParser {} }

    Process { id: sinkSetProc; running: false; stdout: SplitParser {} }
    Process { id: sourceSetProc; running: false; stdout: SplitParser {} }

    Process { id: settingsProc; running: false; stdout: SplitParser {} }

    Process { id: priorityStatusProc; running: false
        stdout: StdioCollector { onStreamFinished: { root.priorityEnabled = text.trim() === "true"; } }
    }

    Process { id: priorityToggleProc; running: false; stdout: SplitParser {} }
    Process { id: eeRestartProc; running: false; stdout: SplitParser {} }
    Process { id: eeOpenProc; running: false; stdout: SplitParser {} }

    Process { id: audioStatusProc; running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split(":", 2);
                    if (parts[0] === "sink") currentSinkId = parts[1];
                    if (parts[0] === "source") currentSourceId = parts[1];
                }
            }
        }
    }

    Process { id: sinkListProc; running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var devices = [];
                var lines = text.trim().split("\n").filter(function(l){return l.length>0;});
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split("→");
                    devices.push({id: parts[0], name: parts[1] || parts[0]});
                    if (parts[0] === currentSinkId) sinkDeviceIndex = i;
                }
                sinkDevices = devices;
            }
        }
    }

    Process { id: sourceListProc; running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var devices = [];
                var lines = text.trim().split("\n").filter(function(l){return l.length>0;});
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split("→");
                    devices.push({id: parts[0], name: parts[1] || parts[0]});
                    if (parts[0] === currentSourceId) sourceDeviceIndex = i;
                }
                sourceDevices = devices;
            }
        }
    }

    function applyEq() {
        var profile = eqProfiles[eqIndex];
        if (!profile) return;
        eqCurrent = profile;
        eqApplyProc.command = ["retro", "audio", "eq", profile];
        eqApplyProc.running = true;
    }

    onPopupOpenChanged: {
        if (controlsPopup.isOpen) {
            // Refresh data on every open (preloaded at shell start, this keeps it current)
            var rd = Quickshell.env("RETRO_DIR");
            eqCurrentProc.command = ["bash", rd + "/scripts/audio_core.sh", "--eq-current"];
            eqCurrentProc.running = true;
            audioStatusProc.command = ["bash", rd + "/scripts/audio_core.sh", "--status"];
            audioStatusProc.running = true;
            sinkListProc.command = ["bash", rd + "/scripts/audio_core.sh", "--list-sinks-named"];
            sinkListProc.running = true;
            sourceListProc.command = ["bash", rd + "/scripts/audio_core.sh", "--list-sources-named"];
            sourceListProc.running = true;
        }
    }

    implicitWidth: 36
    implicitHeight: 36
    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    PwObjectTracker {
        objects: Audio.outputAppNodes
    }

    StyledToolTip {
        show: root.isHovered && !root.popupOpen
        tooltipText: "Audio Controls"
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    // Main button
    StyledRect {
        id: buttonBg
        variant: root.popupOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled

        topLeftRadius: root.vertical ? root.startRadius : root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.vertical ? root.endRadius : root.endRadius

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

        Text {
            anchors.centerIn: parent
            text: Icons.faders
            font.family: Icons.font
            font.pixelSize: 18
            color: root.popupOpen ? buttonBg.item : Styling.srItem("overprimary")
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    settingsProc.command = ["retro", "settings", "audio"];
                    settingsProc.running = true;
                } else {
                    controlsPopup.toggle()
                }
            }
        }
    }

    // Controls popup
    BarPopup {
        id: controlsPopup
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 16

        contentWidth: 240
        // Fixed height calculation to prevent expansion animation on first open
        // 3 rows * 36px + 2 gaps * 12px = 132px
        contentHeight: slidersColumn.implicitHeight + popupPadding * 2

        ColumnLayout {
            id: slidersColumn
            anchors.fill: parent
            spacing: 8

            // Volume Slider
            ControlSliderRow {
                id: volumeRow
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                Layout.rightMargin: 8

                icon: {
                    if (Audio.sink?.audio?.muted)
                        return Icons.speakerSlash;
                    const vol = Audio.sink?.audio?.volume ?? 0;
                    if (vol < 0.01)
                        return Icons.speakerX;
                    if (vol < 0.19)
                        return Icons.speakerNone;
                    if (vol < 0.49)
                        return Icons.speakerLow;
                    return Icons.speakerHigh;
                }
                sliderValue: Audio.sink?.audio?.volume ?? 0
                progressColor: Audio.sink?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
                wavy: true
                wavyAmplitude: Audio.sink?.audio?.muted ? 0.5 : 1.5 * sliderValue
                wavyFrequency: Audio.sink?.audio?.muted ? 1.0 : 8.0 * sliderValue

                onValueChanged: newValue => {
                    if (Audio.sink?.audio) {
                        Audio.sink.audio.volume = newValue;
                    }
                }

                onIconClicked: {
                    if (Audio.sink?.audio) {
                        Audio.sink.audio.muted = !Audio.sink.audio.muted;
                    }
                }

                Connections {
                    target: Audio.sink?.audio ?? null
                    ignoreUnknownSignals: true
                    function onVolumeChanged() {
                        if (Audio.sink?.audio) {
                            volumeRow.sliderValue = Audio.sink.audio.volume;
                        }
                    }
                }
            }

            // Microphone Slider
            ControlSliderRow {
                id: micRow
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                Layout.rightMargin: 8

                icon: Audio.source?.audio?.muted ? Icons.micSlash : Icons.mic
                sliderValue: Audio.source?.audio?.volume ?? 0
                progressColor: Audio.source?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
                wavy: true
                wavyAmplitude: Audio.source?.audio?.muted ? 0.5 : 1.5 * sliderValue
                wavyFrequency: Audio.source?.audio?.muted ? 1.0 : 8.0 * sliderValue

                onValueChanged: newValue => {
                    if (Audio.source?.audio) {
                        Audio.source.audio.volume = newValue;
                    }
                }

                onIconClicked: {
                    if (Audio.source?.audio) {
                        Audio.source.audio.muted = !Audio.source.audio.muted;
                    }
                }

                Connections {
                    target: Audio.source?.audio ?? null
                    ignoreUnknownSignals: true
                    function onVolumeChanged() {
                        if (Audio.source?.audio) {
                            micRow.sliderValue = Audio.source.audio.volume;
                        }
                    }
                }
            }

            // Output device switcher
            StyledCombo {
                Layout.fillWidth: true
                visible: sinkDevices.length > 0
                model: sinkDevices.map(function(d) { return d.name })
                currentIndex: sinkDeviceIndex
                onActivated: index => {
                    if (index < sinkDevices.length) {
                        sinkDeviceIndex = index;
                        sinkSetProc.command = ["retro", "audio", "set-sink", sinkDevices[index].id];
                        sinkSetProc.running = true;
                    }
                }
            }

            // Input device switcher
            StyledCombo {
                Layout.fillWidth: true
                visible: sourceDevices.length > 0
                model: sourceDevices.map(function(d) { return d.name })
                currentIndex: sourceDeviceIndex
                onActivated: index => {
                    if (index < sourceDevices.length) {
                        sourceDeviceIndex = index;
                        sourceSetProc.command = ["retro", "audio", "set-source", sourceDevices[index].id];
                        sourceSetProc.running = true;
                    }
                }
            }

            // EQ Profile selector
            StyledCombo {
                Layout.fillWidth: true
                visible: eqProfiles.length > 0
                model: eqProfiles
                currentIndex: eqIndex
                onActivated: index => {
                    eqIndex = index;
                    applyEq();
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 0
            }

            // Per-app mixer
            Repeater {
                id: appMixer
                model: {
                    var apps = [];
                    for (var i = 0; i < Audio.outputAppNodes.length; i++) {
                        var n = Audio.outputAppNodes[i];
                        var name = Audio.appNodeDisplayName(n);
                        var nodeName = (n?.properties?.["node.name"] || n?.name || "").toLowerCase();
                        var display = name.toLowerCase();
                        var blacklisted = false;
                        for (var b = 0; b < root.appNodeBlacklist.length; b++) {
                            if (root.appNodeBlacklist[b].test(name) || root.appNodeBlacklist[b].test(nodeName) || root.appNodeBlacklist[b].test(display)) {
                                blacklisted = true;
                                break;
                            }
                        }
                        if (blacklisted) continue;
                        if (n.audio && name && name !== "Unknown") apps.push(n);
                    }
                    return apps;
                }
                delegate: Rectangle {
                    color: "transparent"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    Layout.rightMargin: 8
                    required property var modelData
                    property var node: modelData
                    property string appName: Audio.appNodeDisplayName(node)
                    property string iconName: root.appIcon(appName)
                    property bool hasIcon: iconName.length > 0
                    property bool hovered: false

                    HoverHandler {
                        onHoveredChanged: parent.hovered = hovered
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: 6

                        // App icon (click to mute) or truncated name fallback
                        Item {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 24
                            visible: hasIcon

                            Text {
                                anchors.centerIn: parent
                                text: iconName
                                font.family: Icons.font
                                font.pixelSize: 15
                                textFormat: Text.RichText
                                color: iconMouseArea.containsMouse ? Styling.srItem("overprimary") : Colors.overBackground
                            }

                            MouseArea {
                                id: iconMouseArea
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (node.audio)
                                        node.audio.muted = !node.audio.muted;
                                }
                            }
                        }

                        Text {
                            visible: !hasIcon
                            Layout.preferredWidth: 60
                            text: appName
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.overBackground
                            elide: Text.ElideRight
                            opacity: 0.8
                        }

                        StyledSlider {
                            id: appSlider
                            Layout.fillWidth: true
                            height: 14
                            value: parent.parent.node?.audio?.volume ?? 0
                            thickness: 2
                            handleSpacing: 0
                            wavy: true
                            wavyAmplitude: parent.parent.node?.audio?.muted ? 0.5 : 1.5 * value
                            wavyFrequency: parent.parent.node?.audio?.muted ? 1.0 : 8.0 * value
                            progressColor: parent.parent.node?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
                            backgroundColor: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.15)

                            onValueChanged: {
                                Audio.setNodeVolume(parent.parent.node, value);
                            }

                            Connections {
                                target: parent.parent.node?.audio ?? null
                                ignoreUnknownSignals: true
                                function onVolumeChanged() {
                                    if (!appSlider.isDragging)
                                        appSlider.value = parent.parent.node?.audio?.volume ?? 0;
                                }
                                function onMutedChanged() {
                                    if (!appSlider.isDragging)
                                        appSlider.value = parent.parent.node?.audio?.volume ?? 0;
                                }
                            }
                        }

                        StyledToolTip {
                            visible: parent.parent.hovered
                            tooltipText: appName
                        }
                    }
                }
            }

                        // Action buttons
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.actionButtonHeight
                spacing: root.actionButtonSpacing

                Repeater {
                    model: root.actionButtons

                    delegate: StyledRect {
                        id: actionButton
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.preferredHeight: root.actionButtonHeight

                        readonly property bool isSelected: actionButton.modelData.isSelected
                        readonly property bool isFirst: index === 0
                        readonly property bool isLast: index === root.actionButtons.length - 1
                        property bool buttonHovered: false

                        readonly property real defaultRadius: Styling.radius(root.actionRadiusOffset)
                        readonly property real selectedRadius: Styling.radius(root.actionRadiusOffset) / 2

                        variant: isSelected ? "primary" : (buttonHovered ? "focus" : "common")
                        enableShadow: false

                        topLeftRadius: isFirst ? defaultRadius : selectedRadius
                        bottomLeftRadius: isFirst ? defaultRadius : selectedRadius
                        topRightRadius: isLast ? defaultRadius : selectedRadius
                        bottomRightRadius: isLast ? defaultRadius : selectedRadius

                        Text {
                            anchors.centerIn: parent
                            text: actionButton.modelData.icon
                            font.family: Icons.font
                            font.pixelSize: root.actionIconSize
                            color: actionButton.item
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: actionButton.buttonHovered = true
                            onExited: actionButton.buttonHovered = false
                            onClicked: {
                                if (actionButton.modelData.onClicked)
                                    actionButton.modelData.onClicked();
                            }
                        }

                        StyledToolTip {
                            show: actionButton.buttonHovered
                            tooltipText: actionButton.modelData.tooltip
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: controlsPopup
        ignoreUnknownSignals: true
        function onIsOpenChanged() {
            if (controlsPopup.isOpen) {
                // Refresh priority state (preloaded on startup)
                priorityStatusProc.command = ["bash", "-c", "source \"$RETRO_DIR/lib/variable.sh\"; get_var \"AUDIO_PRIORITY_ENABLED\" \"true\""];
                priorityStatusProc.running = true;
            }
        }
    }

    Component.onCompleted: {
        // Preload all audio device/EQ data on shell start
        var rd = Quickshell.env("RETRO_DIR");
        eqCurrentProc.command = ["bash", rd + "/scripts/audio_core.sh", "--eq-current"];
        eqCurrentProc.running = true;
        eqListProc.command = ["bash", rd + "/scripts/audio_core.sh", "--eq-list"];
        eqListProc.running = true;
        audioStatusProc.command = ["bash", rd + "/scripts/audio_core.sh", "--status"];
        audioStatusProc.running = true;
        sinkListProc.command = ["bash", rd + "/scripts/audio_core.sh", "--list-sinks-named"];
        sinkListProc.running = true;
        sourceListProc.command = ["bash", rd + "/scripts/audio_core.sh", "--list-sources-named"];
        sourceListProc.running = true;
        priorityStatusProc.command = ["bash", "-c", "source \"$RETRO_DIR/lib/variable.sh\"; get_var \"AUDIO_PRIORITY_ENABLED\" \"true\""];
        priorityStatusProc.running = true;

        // Initialize slider values
        if (Audio.sink?.audio)
            volumeRow.sliderValue = Audio.sink.audio.volume;
        if (Audio.source?.audio)
            micRow.sliderValue = Audio.source.audio.volume;
    }
}

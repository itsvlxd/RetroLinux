import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config
import qs.modules.widgets.desktop

// Desktop power widget — 2x2 (160x160) power profiles & thermals.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    property string variant: "compact"

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            property var wattMap: ({})

            function refreshWatt() {
                wattProc.command = ["bash", Quickshell.env("RETRO_DIR") + "/scripts/power_core.sh", "--list"];
                wattProc.running = true;
            }

            function currentWatts() {
                var src = Battery.isPluggedIn ? "ac" : "bat";
                var prf = (PowerProfile.currentProfile || "balanced").replace("power-", "");
                var v = content.wattMap[src + "_" + prf];
                return (v !== undefined && v > 0) ? v : 0;
            }

            Process {
                id: wattProc
                running: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        var map = {};
                        var lines = text.trim().split("\n");
                        for (var i = 0; i < lines.length; i++) {
                            var parts = lines[i].split(": ");
                            if (parts.length === 2) {
                                map[parts[0].replace("PWR_", "").toLowerCase()] = parseInt(parts[1]);
                            }
                        }
                        content.wattMap = map;
                    }
                }
            }

            Connections {
                target: PowerProfile
                function onCurrentProfileChanged() { content.refreshWatt(); }
            }

            Component.onCompleted: content.refreshWatt()

            PowerCard {
                anchors.fill: parent
                variant: root.variant
                activeProfile: PowerProfile.currentProfile
                powerDrawWatts: content.currentWatts()
                cpuTempC: SystemResources.cpuTemp
                gpuTempC: SystemResources.gpuTemp
                fanSpeedRpm: SystemResources.fanRpm
                profiles: [
                    { id: "power-saver", label: "Saver", icon: Icons.powerSave },
                    { id: "balanced", label: "Balanced", icon: Icons.balanced },
                    { id: "performance", label: "Perf", icon: Icons.performance }
                ]
                onProfileSelected: function (id) { PowerProfile.setProfile(id); }
            }
        }
    }
}
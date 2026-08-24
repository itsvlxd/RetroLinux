import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.theme
import qs.config
import qs.modules.widgets.desktop

// Desktop world clock — 2x4 (320x160) showing up to 4 timezones.
// Timezones are configured from Settings (stored in the widget entry as
// "timezones": ["UTC", "America/New_York", ...]). Offsets are resolved once
// (and refreshed every 10 min to account for DST changes).
WidgetHost {
    id: root

    implicitWidth: 320
    implicitHeight: 160
    contentMargins: 0

    readonly property var timezones: (root.widgetData && root.widgetData.timezones && root.widgetData.timezones.length > 0)
        ? root.widgetData.timezones : ["UTC"]

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            property int tick: 0
            property var offsets: ({})

            function parseOffset(str) {
                str = (str || "").trim();
                if (str.length < 5) return 0;
                var sign = str[0] === "-" ? -1 : 1;
                var hh = parseInt(str.substring(1, 3), 10) || 0;
                var mm = parseInt(str.substring(3, 5), 10) || 0;
                return sign * (hh * 60 + mm);
            }

            function shortName(zone) {
                var parts = String(zone).split("/");
                var last = parts[parts.length - 1].replace(/_/g, " ");
                return last.length > 11 ? last.substring(0, 10) + "…" : last;
            }

            function offsetFor(zone) {
                var off = content.offsets[zone];
                return off !== undefined ? off : 0;
            }

            function timeFor(zone) {
                content.tick;
                var t = new Date(Date.now() + content.offsetFor(zone) * 60000);
                var hh = t.getUTCHours();
                var mm = t.getUTCMinutes();
                return (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" : "") + mm;
            }

            function dayFor(zone) {
                content.tick;
                var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                var t = new Date(Date.now() + content.offsetFor(zone) * 60000);
                return days[t.getUTCDay()];
            }

            function refreshOffsets() {
                if (!root.timezones || root.timezones.length === 0) return;
                var cmd = "for z in";
                for (var i = 0; i < root.timezones.length; i++) {
                    cmd += " '" + String(root.timezones[i]).replace(/'/g, "") + "'";
                }
                cmd += "; do echo \"$z|$(TZ=$z date +%z)\"; done";
                tzProc.command = ["bash", "-c", cmd];
                tzProc.running = true;
            }

            Process {
                id: tzProc
                running: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        var out = text.trim();
                        if (!out) return;
                        var lines = out.split("\n");
                        for (var i = 0; i < lines.length; i++) {
                            var parts = lines[i].split("|");
                            if (parts.length === 2) {
                                content.offsets[parts[0]] = content.parseOffset(parts[1]);
                            }
                        }
                        tzTimer.restart();
                    }
                }
            }

            // Re-resolve offsets periodically (DST changes etc.)
            Timer {
                id: tzTimer
                interval: 600000
                onTriggered: content.refreshOffsets()
            }

            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: content.tick++
            }

            Component.onCompleted: content.refreshOffsets()

            Connections {
                target: root
                function onWidgetDataChanged() {
                    content.refreshOffsets();
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                Repeater {
                    model: root.timezones
                    delegate: Item {
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                text: content.shortName(modelData)
                                color: Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillWidth: true
                            }

                            Text {
                                text: content.timeFor(modelData)
                                color: Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: 26
                                font.weight: Font.Bold
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: content.dayFor(modelData)
                                color: Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: 10
                                opacity: 0.7
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
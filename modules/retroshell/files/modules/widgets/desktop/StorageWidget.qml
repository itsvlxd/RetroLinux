import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config
import qs.modules.widgets.desktop

// Desktop storage widget — 2x2 (160x160) Apple-style device storage card.
// Shows real usage for the configured storage device (settings → Desktop →
// Device Storage → pick device). Falls back to sample data until measured.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    readonly property string device: (root.widgetData && root.widgetData.device)
        ? String(root.widgetData.device) : ""

    property bool wide: false
    property bool showBorder: true

    property var sampleSegments: [
        { label: "System", sizeGB: 120, color: "#FF3B30", striped: false },
        { label: "Home", sizeGB: 180, color: "#34C759", striped: false },
        { label: "Apps", sizeGB: 80, color: "#007AFF", striped: false },
        { label: "Cache", sizeGB: 45, color: "#FF9500", striped: false },
        { label: "Root", sizeGB: 30, color: "#D1D1D6", striped: true },
        { label: "Other", sizeGB: 57, color: "#8E8E93", striped: true }
    ]
    property real sampleTotal: 512

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            property var segments: root.sampleSegments
            property real totalGB: root.sampleTotal
            property real usedGB: -1

            function refresh() {
                var dev = root.device;
                if (!dev && SystemResources.validDisks.length > 0)
                    dev = SystemResources.validDisks[0];
                if (!dev) dev = "/";
                storageProc.command = ["bash", "-c",
                    "timeout 45 python3 " + Quickshell.shellDir + "/scripts/storage_buckets.py '" + String(dev).replace(/'/g, "") + "'"];
                storageProc.running = true;
            }

            Process {
                id: storageProc
                running: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        var out = text.trim();
                        if (!out) return;
                        try {
                            var d = JSON.parse(out);
                            if (d.buckets && d.buckets.length > 0) {
                                content.segments = d.buckets;
                                if (d.totalGB) content.totalGB = d.totalGB;
                                if (d.usedGB) content.usedGB = d.usedGB;
                            }
                        } catch (e) {
                            console.warn("StorageWidget: parse error", e);
                        }
                    }
                }
            }

            // Re-measure periodically (sizes change over time)
            Timer {
                id: refreshTimer
                interval: 600000
                onTriggered: content.refresh()
            }

            Connections {
                target: root
                function onWidgetDataChanged() { content.refresh(); }
            }

            Component.onCompleted: {
                content.refresh();
                refreshTimer.start();
            }

            DeviceStorageCard {
                anchors.fill: parent
                wide: root.wide
                showBorder: root.showBorder
                title: "Device Storage"
                totalGB: content.totalGB
                usedGB: content.usedGB
                segments: content.segments
            }
        }
    }
}
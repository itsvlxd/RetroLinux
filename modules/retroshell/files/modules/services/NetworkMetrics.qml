pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Real-time network metrics for the Network widget.
 * Runs a single streaming process (shared by all network widgets).
 */
Singleton {
    id: root

    property string interfaceName: ""
    property real downloadMbps: 0
    property real uploadMbps: 0
    property string localIp: ""
    property string publicIp: ""
    property bool publicIpValid: false

    property var downloadHistory: []
    property var uploadHistory: []
    property int maxHistory: 60

    Process {
        id: monitor
        running: true
        command: ["python3", Quickshell.shellDir + "/scripts/network_monitor.py"]

        stdout: SplitParser {
            onRead: data => {
                try {
                    const s = JSON.parse(data);
                    root.interfaceName = s.interface || root.interfaceName;
                    root.downloadMbps = s.download || 0;
                    root.uploadMbps = s.upload || 0;
                    root.localIp = s.localIp || "";
                    if (s.publicIpValid) {
                        root.publicIp = s.publicIp;
                        root.publicIpValid = true;
                    }

                    const dh = root.downloadHistory.slice();
                    dh.push(s.download || 0);
                    if (dh.length > root.maxHistory) dh.shift();
                    root.downloadHistory = dh;

                    const uh = root.uploadHistory.slice();
                    uh.push(s.upload || 0);
                    if (uh.length > root.maxHistory) uh.shift();
                    root.uploadHistory = uh;
                } catch (e) {
                    console.warn("NetworkMetrics: parse error", e);
                }
            }
        }
    }
}
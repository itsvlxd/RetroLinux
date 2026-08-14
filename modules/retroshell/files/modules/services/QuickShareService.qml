pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string corePath: (Quickshell.env("RETRO_DIR") || "/opt/retrolinux") + "/scripts/quickshare_core.sh"

    property bool running: false
    property string downloadDir: ""
    property bool scanning: false
    property bool isUpdating: false
    property bool sending: false
    property int sendProgress: 0
    property string sendingFile: ""

    property bool _pendingToggle: false

    property list<var> deviceList: []

    onRunningChanged: {
        if (!running) {
            root.deviceList = [];
        }
    }

    function refresh() {
        root.isUpdating = true;
        statusProc.command = ["bash", root.corePath, "--status"];
        statusProc.running = true;
    }

    function setEnabled(enabled) {
        root.running = enabled;
        actionProc.command = ["bash", root.corePath, enabled ? "--start" : "--stop"];
        actionProc.running = true;
    }

    function toggle() {
        root._pendingToggle = true;
        root.refresh();
    }

    function scan() {
        root.scanning = true;
        scanProc.command = ["bash", root.corePath, "--scan"];
        scanProc.running = true;
    }

    function sendTo(device) {
        if (!device || !device.address || !device.port) {
            return;
        }
        filePickProc.targetName = device.name || "device";
        filePickProc.targetAddress = device.address;
        filePickProc.targetPort = device.port;
        filePickProc.command = ["bash", root.corePath, "--pick-file"];
        filePickProc.running = true;
    }

    Process {
        id: statusProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.trim().split("|");
                if (parts.length >= 2) {
                    root.running = parts[0] === "running";
                    root.downloadDir = parts[1] || "";
                }
                if (root._pendingToggle) {
                    root._pendingToggle = false;
                    root.setEnabled(!root.running);
                }
                root.isUpdating = false;
            }
        }
    }

    Process {
        id: actionProc
        running: false
        stdout: SplitParser {}
        onRunningChanged: {
            if (!running) {
                root.refresh();
            }
        }
    }

    Process {
        id: scanProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var list = [];
                var lines = text.trim().split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split("|");
                    if (parts.length >= 3) {
                        list.push({
                            name: parts[0],
                            address: parts[1],
                            port: parts[2],
                            type: parts.length > 3 ? parts[3] : ""
                        });
                    }
                }
                root.deviceList = list;
                root.scanning = false;
            }
        }
    }

    Process {
        id: filePickProc
        property string targetName: ""
        property string targetAddress: ""
        property string targetPort: ""
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var out = text.trim();
                if (out.indexOf("OK|") === 0) {
                    var path = out.substring(3);
                    if (path.length > 0) {
                        sendProc.targetName = filePickProc.targetName;
                        root.sending = true;
                        root.sendProgress = 0;
                        root.sendingFile = path.split("/").pop();
                        sendProc.command = ["bash", root.corePath, "--send", filePickProc.targetAddress, filePickProc.targetPort, path];
                        sendProc.running = true;
                    }
                }
            }
        }
    }

    Process {
        id: sendProc
        property string targetName: ""
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                var line = data ? data.trim() : "";
                if (line.indexOf("PROGRESS|") === 0) {
                    var p = line.split("|");
                    if (p.length >= 2) {
                        root.sendProgress = parseInt(p[1]) || 0;
                    }
                } else if (line.indexOf("OK|") === 0) {
                    notifyProc.command = ["notify-send", "-a", "RetroLinux", "-i", "network-transmit-receive-symbolic",
                        "Quick Share: Sent", "File sent to " + sendProc.targetName];
                    notifyProc.running = true;
                } else if (line.indexOf("ERR|") === 0) {
                    var reason = line.substring(4);
                    var msg;
                    var title = "Quick Share: Send failed";
                    if (reason === "receiver_canceled") {
                        title = "Quick Share: Transfer canceled";
                        msg = sendProc.targetName + " stopped the transfer";
                    } else if (reason === "canceled") {
                        title = "Quick Share: Transfer canceled";
                        msg = "The transfer was canceled";
                    } else if (reason === "REJECT") {
                        msg = "The device declined, open Quick Share on " + sendProc.targetName + " and accept";
                    } else if (reason.indexOf("not_a_file") === 0) {
                        msg = "The selected file is no longer available";
                    } else if (reason === "file_not_found") {
                        msg = "The selected file was not found";
                    } else if (reason === "bad_target") {
                        msg = "The receiving device is no longer reachable";
                    } else {
                        msg = reason || "Unknown error";
                    }
                    notifyProc.command = ["notify-send", "-a", "RetroLinux", "-i", "network-transmit-receive-symbolic",
                        title, msg];
                    notifyProc.running = true;
                }
            }
        }
        onRunningChanged: {
            if (!running) {
                root.sending = false;
                root.sendProgress = 0;
                root.sendingFile = "";
                root.scan();
            }
        }
    }

    Process {
        id: notifyProc
        running: false
        stdout: SplitParser {}
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        root.refresh();
    }
}

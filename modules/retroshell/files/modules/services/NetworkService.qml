pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals

Singleton {
    id: root

    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    property bool wifiScanning: false
    property var lastScanTime: 0
    property bool wifiConnecting: isUpdating && wifiStatus === "connecting"
    property bool isUpdating: false
    property bool wasEnabledBeforeSleep: false

    property var suspendConnections: Connections {
        target: SuspendManager
        function onPreparingForSleep() {
            root.wasEnabledBeforeSleep = root.wifiEnabled;
        }
        function onWakingUp() {
            if (root.wasEnabledBeforeSleep) {
                root.enableWifi(true);
            }
        }
    }

    property WifiAccessPoint wifiConnectTarget: null
    readonly property list<WifiAccessPoint> wifiNetworks: []
    property WifiAccessPoint active: null

    function updateActive() {
        for (let i = 0; i < wifiNetworks.length; i++) {
            if (wifiNetworks[i].active) {
                active = wifiNetworks[i];
                return;
            }
        }
        active = null;
    }

    property string wifiStatus: "disconnected"

    property string networkName: ""
    property int networkStrength: 0

    property list<var> friendlyWifiNetworks: []

    function updateFriendlyList() {
        friendlyWifiNetworks = [...wifiNetworks].sort((a, b) => {
            if (a.active && !b.active)
                return -1;
            if (!a.active && b.active)
                return 1;
            return b.strength - a.strength;
        });
        updateActive();
    }

    Component {
        id: asyncProcessComp
        Process {
            id: internalProc
            property var resolve
            property var reject
            property string buffer: ""
            property string errorBuffer: ""
            
            stdout: SplitParser {
                onRead: data => internalProc.buffer += data + "\n"
            }
            
            stderr: SplitParser {
                onRead: data => internalProc.errorBuffer += data + "\n"
            }
            
            onExited: (exitCode, exitStatus) => {
                if (exitCode === 0) resolve(buffer.trim());
                else reject(errorBuffer.trim() || `Process exited with code ${exitCode}`);
                destroy();
            }
        }
    }

    function runAsync(command, environment = {}) {
        return new Promise((resolve, reject) => {
            const proc = asyncProcessComp.createObject(root, {
                command: command,
                environment: environment,
                resolve: resolve,
                reject: reject
            });
            proc.running = true;
        });
    }

    function enableWifi(enabled = true): void {
        isUpdating = true;
        const cmd = enabled ? "on" : "off";
        runAsync(["nmcli", "radio", "wifi", cmd]).then(() => {
            update();
            isUpdating = false;
        }).catch(e => {
            isUpdating = false;
        });
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(): void {
        const now = Date.now();
        if (now - lastScanTime < 10000) { // 10s throttle
            getNetworks.running = true;
            return;
        }
        
        lastScanTime = now;
        wifiScanning = true;
        runAsync(["nmcli", "dev", "wifi", "list", "--rescan", "yes"]).then(() => {
            update();
            getNetworks.running = true;
            wifiScanning = false;
        }).catch(e => {
            wifiScanning = false;
        });
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        isUpdating = true;
        runAsync(["nmcli", "dev", "wifi", "connect", accessPoint.ssid]).then(() => {
            getNetworks.running = true;
            root.wifiConnectTarget = null;
            isUpdating = false;
        }).catch(e => {
            if (e.includes("Secrets were required")) {
                accessPoint.askingPassword = true;
            }
            root.wifiConnectTarget = null;
            isUpdating = false;
        });
    }

    function disconnectWifiNetwork(): void {
        if (active) {
            isUpdating = true;
            runAsync(["nmcli", "connection", "down", active.ssid]).then(() => {
                getNetworks.running = true;
                isUpdating = false;
            }).catch(e => {
                isUpdating = false;
            });
        }
    }

    function changePassword(network: WifiAccessPoint, password: string): void {
        network.askingPassword = false;
        isUpdating = true;
        runAsync(["bash", "-c", `nmcli connection modify "${network.ssid}" wifi-sec.psk "$PASSWORD"`], { "PASSWORD": password }).then(() => {
            connectToWifiNetwork(network);
        }).then(() => {
            isUpdating = false;
        }).catch(e => {
            isUpdating = false;
        });
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]);
    }

    // WiFi icon by strength
    function wifiIconForStrength(strength: int): string {
        if (strength > 80) return Icons.wifiHigh;
        if (strength > 55) return Icons.wifiMedium;
        if (strength > 30) return Icons.wifiLow;
        if (strength > 0) return Icons.wifiNone;
        return Icons.wifiOff;
    }

    // Update status
    Timer {
        id: updateDebouncer
        interval: 200
        repeat: false
        onTriggered: root.performUpdate()
    }

    function update() {
        updateDebouncer.restart();
    }

    function performUpdate() {
        if (isUpdating) return;
        
        // Skip/delay updates if UI closed
        // nmcli monitor is event-based; safe to run.
        // Optimization: Only update signal strength when UI open
        const uiOpen = GlobalStates.dashboardOpen || GlobalStates.launcherOpen || GlobalStates.overviewOpen;
        
        isUpdating = true;
        updateConnectionType.startCheck();
        wifiStatusProcess.running = true;
        updateNetworkName.running = true;
        getDnsProvider();
        
        if (uiOpen) {
            updateNetworkStrength.running = true;
        }
    }

    Process {
        id: subscriber
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: root.update()
        }
    }

    Process {
        id: updateConnectionType
        property string buffer: ""
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE d status && nmcli -t -f CONNECTIVITY g"]
        running: true
        function startCheck() {
            buffer = "";
            updateConnectionType.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                updateConnectionType.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            const lines = updateConnectionType.buffer.trim().split('\n');
            const connectivity = lines.pop();
            let hasEthernet = false;
            let hasWifi = false;
            let wifiStatus = "disconnected";
            lines.forEach(line => {
                if (line.includes("ethernet") && line.includes("connected"))
                    hasEthernet = true;
                else if (line.includes("wifi:")) {
                    if (line.includes("disconnected")) {
                        wifiStatus = "disconnected";
                    } else if (line.includes("connected")) {
                        hasWifi = true;
                        wifiStatus = "connected";
                        if (connectivity === "limited") {
                            hasWifi = false;
                            wifiStatus = "limited";
                        }
                    } else if (line.includes("connecting")) {
                        wifiStatus = "connecting";
                    } else if (line.includes("unavailable")) {
                        wifiStatus = "disabled";
                    }
                }
            });
            root.wifiStatus = wifiStatus;
            root.ethernet = hasEthernet;
            root.wifi = hasWifi;
            root.isUpdating = false;
        }
    }

    Process {
        id: updateNetworkName
        command: ["sh", "-c", "nmcli -t -f NAME c show --active | head -1"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.networkName = data;
            }
        }
    }

    Process {
        id: updateNetworkStrength
        running: true
        command: ["sh", "-c", "nmcli -f IN-USE,SIGNAL,SSID device wifi | awk '/^\\*/{if (NR!=1) {print $2}}'"]
        stdout: SplitParser {
            onRead: data => {
                root.networkStrength = parseInt(data) || 0;
            }
        }
    }

    Process {
        id: wifiStatusProcess
        command: ["nmcli", "radio", "wifi"]
        running: true
        environment: ({
            LANG: "C.UTF-8",
            LC_ALL: "C.UTF-8"
        })
        stdout: SplitParser {
            onRead: data => {
                root.wifiEnabled = data.trim() === "enabled";
            }
        }
    }

    Process {
        id: getNetworks
        running: false
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "d", "w"]
        environment: ({
            LANG: "C.UTF-8",
            LC_ALL: "C.UTF-8"
        })
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                getNetworks.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            const text = getNetworks.buffer;
            getNetworks.buffer = "";
            
            Qt.callLater(() => {
                if (text.length === 0) {
                    root.updateFriendlyList();
                    return;
                }

                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep = /\\:/g;
                const rep2 = new RegExp(PLACEHOLDER, "g");

                const lines = text.trim().split("\n");
                const networkMap = new Map();

                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].replace(rep, PLACEHOLDER);
                    const net = line.split(":");
                    if (net.length < 6) continue;

                    const ssid = net[3] || "";
                    if (!ssid) continue;

                    const network = {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]) || 0,
                        frequency: parseInt(net[2]) || 0,
                        ssid: ssid,
                        bssid: (net[4] || "").replace(rep2, ":"),
                        security: net[5] || ""
                    };

                    const existing = networkMap.get(ssid);
                    if (!existing || (network.active && !existing.active) || (!network.active && !existing.active && network.strength > existing.strength)) {
                        networkMap.set(ssid, network);
                    }
                }

                const wifiNetworksData = Array.from(networkMap.values());
                const rNetworks = root.wifiNetworks;

                // Sync with new data
                // 1. Remove gone networks
                for (let i = rNetworks.length - 1; i >= 0; i--) {
                    const rn = rNetworks[i];
                    const found = wifiNetworksData.find(n => n.frequency === rn.frequency && n.ssid === rn.ssid && n.bssid === rn.bssid);
                    if (!found) {
                        rNetworks.splice(i, 1);
                        rn.destroy();
                    }
                }

                // 2. Add/update networks
                for (let i = 0; i < wifiNetworksData.length; i++) {
                    const data = wifiNetworksData[i];
                    const existing = rNetworks.find(n => n.frequency === data.frequency && n.ssid === data.ssid && n.bssid === data.bssid);
                    if (existing) {
                        existing.lastIpcObject = data;
                    } else {
                        rNetworks.push(apComp.createObject(root, {
                            lastIpcObject: data
                        }));
                    }
                }

                root.updateFriendlyList();
            });
        }
    }

    Component {
        id: apComp
        WifiAccessPoint {}
    }

    // Net stats properties
    property bool netStatsActive: false
    property real netPingMs: 0
    property real netPacketLoss: 0
    property string netDeviceIp: "N/A"
    property string netGatewayIp: "N/A"
    property real netDownloadSpeed: 0
    property real netUploadSpeed: 0
    property real netTotalDownloaded: 0
    property real netTotalUploaded: 0
    property real _netPrevRxBytes: 0
    property real _netPrevTxBytes: 0
    property real _netPrevTimestamp: 0

    // DNS provider
    property string netDnsProvider: "cloudflare"

    function setDnsProvider(provider) {
        var rd = Quickshell.env("RETRO_DIR");
        dnsProviderProc.command = ["bash", rd + "/scripts/network_core.sh", "--set-dns-provider", provider];
        dnsProviderProc.running = true;
    }

    function getDnsProvider() {
        var rd = Quickshell.env("RETRO_DIR");
        dnsGetProc.command = ["bash", rd + "/scripts/network_core.sh", "--get-dns-provider"];
        dnsGetProc.running = true;
    }

    Process {
        id: dnsProviderProc
        running: false
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => dnsProviderProc.buffer += data + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            var text = dnsProviderProc.buffer.trim();
            dnsProviderProc.buffer = "";
            if (text.includes("result=success")) {
                var providerMatch = text.match(/provider=(\w+)/);
                if (providerMatch) root.netDnsProvider = providerMatch[1];
            }
        }
    }

    Process {
        id: dnsGetProc
        running: false
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => dnsGetProc.buffer += data + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            var text = dnsGetProc.buffer.trim();
            dnsGetProc.buffer = "";
            var providerMatch = text.match(/provider=(\w+)/);
            if (providerMatch) root.netDnsProvider = providerMatch[1];
        }
    }

    // Speed test
    property bool speedTestRunning: false
    property string speedTestPhase: ""
    property real speedTestPing: 0
    property real speedTestDown: 0
    property real speedTestUp: 0

    function runSpeedTest() {
        if (speedTestRunning) return;
        speedTestRunning = true;
        speedTestPhase = "ping";
        speedTestPing = 0;
        speedTestDown = 0;
        speedTestUp = 0;
        var rd = Quickshell.env("RETRO_DIR");
        speedTestProc.command = ["bash", rd + "/scripts/network_core.sh", "--speed-test"];
        speedTestProc.running = true;
    }

    Process {
        id: speedTestProc
        running: false
        stdout: SplitParser {
            onRead: data => {
                try {
                    var msg = JSON.parse(data.trim());
                    if (msg.type === "phase") {
                        root.speedTestPhase = msg.phase;
                    } else if (msg.type === "ping") {
                        root.speedTestPing = msg.value;
                    } else if (msg.type === "download") {
                        root.speedTestDown = msg.value;
                    } else if (msg.type === "download_done") {
                        root.speedTestDown = msg.value;
                    } else if (msg.type === "upload") {
                        root.speedTestUp = msg.value;
                    } else if (msg.type === "upload_done") {
                        root.speedTestUp = msg.value;
                    } else if (msg.type === "done") {
                        root.speedTestRunning = false;
                        root.speedTestPhase = "";
                    } else if (msg.type === "error") {
                        root.speedTestRunning = false;
                        root.speedTestPhase = "";
                    }
                } catch (e) {}
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.speedTestRunning = false;
            root.speedTestPhase = "";
        }
    }

    Timer {
        id: fastStatsTimer
        interval: 2000
        repeat: true
        running: root.netStatsActive
        onTriggered: root._pollNetStats()
    }

    Timer {
        id: slowStatsTimer
        interval: 60000
        repeat: true
        running: !root.netStatsActive
        onTriggered: root._pollNetStats()
    }

    function _pollNetStats() {
        var rd = Quickshell.env("RETRO_DIR");
        netStatsProc.command = ["bash", rd + "/scripts/network_core.sh", "--net-stats"];
        netStatsProc.running = true;
    }

    Process {
        id: netStatsProc
        running: false
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => netStatsProc.buffer += data + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            var text = netStatsProc.buffer.trim();
            netStatsProc.buffer = "";
            var parts = text.split("|");
            if (parts.length < 8) return;

            root.netPingMs = parseFloat(parts[0]) || 0;
            root.netPacketLoss = parseFloat(parts[1]) || 0;
            var rxBytes = parseFloat(parts[2]) || 0;
            var txBytes = parseFloat(parts[3]) || 0;
            root.netDeviceIp = parts[4] || "N/A";
            root.netGatewayIp = parts[5] || "N/A";
            root.netTotalDownloaded = parseFloat(parts[6]) || 0;
            root.netTotalUploaded = parseFloat(parts[7]) || 0;

            var now = Date.now();
            if (root._netPrevTimestamp > 0) {
                var elapsed = (now - root._netPrevTimestamp) / 1000;
                if (elapsed > 0) {
                    root.netDownloadSpeed = Math.max(0, (rxBytes - root._netPrevRxBytes) / elapsed);
                    root.netUploadSpeed = Math.max(0, (txBytes - root._netPrevTxBytes) / elapsed);
                }
            }
            root._netPrevRxBytes = rxBytes;
            root._netPrevTxBytes = txBytes;
            root._netPrevTimestamp = now;
        }
    }

    Component.onCompleted: {
        update();
        wifiStatusProcess.running = true;
        _pollNetStats();
    }
}

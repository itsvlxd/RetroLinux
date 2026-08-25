pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    property bool showQr: false
    property string qrImagePath: ""

    function formatBytes(bytes) {
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB";
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB";
        if (bytes >= 1024) return (bytes / 1024).toFixed(1) + " KB";
        return bytes + " B";
    }

    Component.onCompleted: {
        NetworkService.netStatsActive = true;
        initialScanTimer.start();
    }

    Component.onDestruction: {
        NetworkService.netStatsActive = false;
    }

    Timer {
        id: initialScanTimer
        interval: 300
        repeat: false
        onTriggered: {
            NetworkService.rescanWifi();
        }
    }

    Process {
        id: qrGenProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var path = text.trim();
                if (path !== "") {
                    qrImagePath = path;
                    showQr = true;
                    networkList.positionViewAtBeginning();
                }
            }
        }
    }

    ListView {
        id: networkList
        anchors.fill: parent
        clip: true
        spacing: 4
        cacheBuffer: 1000
        reuseItems: true

        model: NetworkService.friendlyWifiNetworks

        header: Item {
            width: networkList.width
            height: titlebar.height
                + (showQr && qrImagePath !== "" ? 196 : 0)
                + (NetworkService.wifi ? 148 : 0)
                + 2

            PanelTitlebar {
                id: titlebar
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                title: "Wi-Fi"
                statusText: NetworkService.wifiConnecting ? "Connecting..." : (NetworkService.wifiStatus === "limited" ? "Limited" : "")
                statusColor: NetworkService.wifiStatus === "limited" ? Colors.warning : Styling.srItem("overprimary")
                showToggle: true
                toggleChecked: NetworkService.wifiStatus !== "disabled"

                actions: [
                    {
                        icon: Icons.qrCode,
                        tooltip: "Share WiFi via QR code",
                        enabled: NetworkService.wifi && NetworkService.active !== null,
                        onClicked: function () {
                            if (showQr) {
                                showQr = false;
                            } else {
                                var rd = Quickshell.env("RETRO_DIR");
                                qrGenProc.command = ["bash", rd + "/scripts/network_core.sh", "--wifi-qr"];
                                qrGenProc.running = true;
                            }
                            networkList.positionViewAtBeginning();
                        }
                    },
                    {
                        icon: Icons.globe,
                        tooltip: "Open captive portal",
                        enabled: NetworkService.wifiStatus === "limited",
                        onClicked: function () {
                            NetworkService.openPublicWifiPortal();
                        }
                    },
                    {
                        icon: Icons.gear,
                        tooltip: "Open Network Settings",
                        onClicked: function () {
                            Quickshell.execDetached(["retro", "settings", "network"]);
                        }
                    },
                    {
                        icon: Icons.sync,
                        tooltip: "Rescan networks",
                        enabled: NetworkService.wifiEnabled,
                        loading: NetworkService.wifiScanning || NetworkService.isUpdating,
                        onClicked: function () {
                            NetworkService.rescanWifi();
                        }
                    }
                ]

                onToggleChanged: checked => {
                    NetworkService.enableWifi(checked);
                    if (checked) {
                        NetworkService.rescanWifi();
                    }
                }
            }

            // QR Code display
            Item {
                id: qrDisplay
                anchors.top: titlebar.bottom
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.contentWidth
                height: showQr && qrImagePath !== "" ? 180 : 0
                visible: showQr && qrImagePath !== ""
                clip: true

                StyledRect {
                    anchors.fill: parent
                    variant: "common"
                    enableShadow: false
                    radius: Styling.radius(0)

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Image {
                            Layout.alignment: Qt.AlignHCenter
                            source: qrImagePath !== "" ? "file://" + qrImagePath : ""
                            Layout.preferredWidth: 130
                            Layout.preferredHeight: 130
                            fillMode: Image.PreserveAspectFit
                            cache: false
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Scan to connect"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overBackground
                            opacity: 0.7
                        }
                    }
                }
            }

            // Network stats card
            Item {
                id: statsCard
                anchors.top: showQr && qrImagePath !== "" ? qrDisplay.bottom : titlebar.bottom
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.contentWidth
                height: NetworkService.wifi ? 88 : 0
                visible: NetworkService.wifi

                StyledRect {
                    anchors.fill: parent
                    variant: "common"
                    enableShadow: false
                    radius: Styling.radius(0)

                    Grid {
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        columns: 2
                        columnSpacing: 16
                        rowSpacing: 2

                        // Ping
                        Item {
                            width: (statsCard.width - 16) / 2
                            height: 14
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text {
                                    text: Icons.clock
                                    font.family: Icons.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: NetworkService.netPingMs.toFixed(0) + " ms"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.bold: true
                                    color: Colors.overBackground
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Packet Loss
                        Item {
                            width: (statsCard.width - 16) / 2
                            height: 14
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text {
                                    text: Icons.wifiX
                                    font.family: Icons.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: NetworkService.netPacketLoss.toFixed(1) + " %"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.bold: true
                                    color: Colors.overBackground
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Downloading
                        Item {
                            width: (statsCard.width - 16) / 2
                            height: 14
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text {
                                    text: Icons.arrowDown
                                    font.family: Icons.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: NetworkService.netDownloadSpeed >= 1048576
                                        ? (NetworkService.netDownloadSpeed / 1048576).toFixed(1) + " MB/s"
                                        : (NetworkService.netDownloadSpeed / 1024).toFixed(1) + " KB/s"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.bold: true
                                    color: Colors.overBackground
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Uploading
                        Item {
                            width: (statsCard.width - 16) / 2
                            height: 14
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text {
                                    text: Icons.arrowUp
                                    font.family: Icons.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: NetworkService.netUploadSpeed >= 1048576
                                        ? (NetworkService.netUploadSpeed / 1048576).toFixed(1) + " MB/s"
                                        : (NetworkService.netUploadSpeed / 1024).toFixed(1) + " KB/s"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.bold: true
                                    color: Colors.overBackground
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Downloaded
                        Item {
                            width: (statsCard.width - 16) / 2
                            height: 14
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text {
                                    text: Icons.arrowFatLinesDown
                                    font.family: Icons.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: formatBytes(NetworkService.netTotalDownloaded)
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.bold: true
                                    color: Colors.overBackground
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Uploaded
                        Item {
                            width: (statsCard.width - 16) / 2
                            height: 14
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text {
                                    text: Icons.arrowUp
                                    font.family: Icons.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: formatBytes(NetworkService.netTotalUploaded)
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.bold: true
                                    color: Colors.overBackground
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // IP Address
                        Item {
                            width: (statsCard.width - 16) / 2
                            height: 14
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text {
                                    text: Icons.globe
                                    font.family: Icons.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: NetworkService.netDeviceIp
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.bold: true
                                    color: Colors.overBackground
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Gateway
                        Item {
                            width: (statsCard.width - 16) / 2
                            height: 14
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text {
                                    text: Icons.globe
                                    font.family: Icons.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: NetworkService.netGatewayIp
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.bold: true
                                    color: Colors.overBackground
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }

            // DNS provider card
            Item {
                id: dnsCard
                anchors.top: statsCard.bottom
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.contentWidth
                height: NetworkService.wifi ? 48 : 0
                visible: NetworkService.wifi

                StyledRect {
                    anchors.fill: parent
                    variant: "common"
                    enableShadow: false
                    radius: Styling.radius(0)

                    Grid {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        columns: 4
                        columnSpacing: 6

                        Repeater {
                            model: [
                                { key: "cloudflare", label: "Cloudflare" },
                                { key: "google", label: "Google" },
                                { key: "cloud9", label: "Cloud9" },
                                { key: "dhcp", label: "DHCP" }
                            ]

                            delegate: Item {
                                required property var modelData
                                width: (dnsCard.width - 28) / 4
                                height: 32

                                property bool isActive: NetworkService.netDnsProvider === modelData.key

                                StyledRect {
                                    anchors.fill: parent
                                    variant: parent.isActive ? "focus" : "common"
                                    radius: Styling.radius(-4)

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-3)
                                        font.bold: parent.parent.isActive
                                        color: parent.parent.isActive ? Colors.overPrimary : Colors.overBackground
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            NetworkService.setDnsProvider(modelData.key);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        delegate: Item {
            required property var modelData
            width: networkList.width
            height: networkItem.height

            WifiNetworkItem {
                id: networkItem
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                network: parent.modelData
            }
        }

        Text {
            anchors.centerIn: parent
            visible: networkList.count === 0 && !NetworkService.wifiScanning
            text: NetworkService.wifiEnabled ? "No networks found" : "Wi-Fi is disabled"
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color: Colors.overSurfaceVariant
        }
    }
}

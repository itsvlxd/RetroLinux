import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config
import qs.modules.widgets.desktop

// Desktop network widget — 2x2 (160x160) network & bandwidth monitor.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    readonly property bool hideIp: (root.widgetData && root.widgetData.hideIp !== undefined)
        ? root.widgetData.hideIp === true : true

    property string variant: "compact"

    contentComponent: Component {
        NetworkCard {
            anchors.fill: parent
            variant: root.variant
            interfaceName: NetworkMetrics.interfaceName
            ssid: NetworkService.networkName
            isConnected: NetworkService.wifiStatus === "connected" || NetworkService.ethernet
            wifiStrength: NetworkService.networkStrength
            wifiEnabled: NetworkService.wifiEnabled
            downloadMbps: NetworkMetrics.downloadMbps
            uploadMbps: NetworkMetrics.uploadMbps
            localIp: NetworkMetrics.localIp
            publicIp: NetworkMetrics.publicIp
            publicIpValid: NetworkMetrics.publicIpValid
            hideIp: root.hideIp
            downloadHistory: NetworkMetrics.downloadHistory
            uploadHistory: NetworkMetrics.uploadHistory
            onToggleWifiRequested: NetworkService.toggleWifi()
        }
    }
}
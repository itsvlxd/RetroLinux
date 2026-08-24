import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config
import qs.modules.widgets.desktop

// Desktop bluetooth widget — 2x2 (160x160) bluetooth & quick pair.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    readonly property string devicePriority: (root.widgetData && root.widgetData.devicePriority)
        ? String(root.widgetData.devicePriority) : "automatic"

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            function typeOf(icon) {
                var ic = String(icon || "");
                if (ic.includes("audio-headset") || ic.includes("headphone") || ic.includes("headset")) return "audio";
                if (ic.includes("input-keyboard")) return "keyboard";
                if (ic.includes("input-mouse")) return "mouse";
                if (ic.includes("input-gaming") || ic.includes("gamepad")) return "gamepad";
                if (ic.includes("phone")) return "phone";
                if (ic.includes("watch")) return "watch";
                if (ic.includes("audio-speakers") || ic.includes("speaker")) return "speaker";
                if (ic.includes("printer")) return "printer";
                if (ic.includes("camera")) return "camera";
                return "other";
            }

            function rank(type) {
                if (root.devicePriority === "automatic") return 0;
                return type === root.devicePriority ? -1 : 1;
            }

            function buildConnected() {
                var out = [];
                var list = BluetoothService.friendlyDeviceList;
                for (var i = 0; i < list.length; i++) {
                    var d = list[i];
                    if (d && d.connected) {
                        out.push({ mac: d.address, name: d.name, type: content.typeOf(d.icon), battery: d.battery });
                    }
                }
                out.sort(function (a, b) { return content.rank(a.type) - content.rank(b.type); });
                return out;
            }

            function buildPaired() {
                var out = [];
                var list = BluetoothService.friendlyDeviceList;
                for (var i = 0; i < list.length; i++) {
                    var d = list[i];
                    if (d && d.paired && !d.connected) {
                        out.push({ mac: d.address, name: d.name, type: content.typeOf(d.icon) });
                    }
                }
                out.sort(function (a, b) { return content.rank(a.type) - content.rank(b.type); });
                return out;
            }

            function buildDiscovered() {
                var out = [];
                var list = BluetoothService.friendlyDeviceList;
                for (var i = 0; i < list.length; i++) {
                    var d = list[i];
                    if (d && !d.paired && !d.connected && d.name && d.name !== "Unknown") {
                        out.push({ mac: d.address, name: d.name, type: content.typeOf(d.icon) });
                    }
                }
                return out;
            }

            // The service's own device poll only runs while the dashboard is
            // open; the desktop needs its own refresh so discovered/connected
            // devices stay live.
            Timer {
                interval: 4000
                running: BluetoothService.enabled
                repeat: true
                onTriggered: BluetoothService.updateDevices()
            }

            Component.onCompleted: BluetoothService.updateDevices()

            BluetoothCard {
                anchors.fill: parent
                isEnabled: BluetoothService.enabled
                isScanning: BluetoothService.discovering
                connectedDevices: content.buildConnected()
                pairedDevices: content.buildPaired()
                discoveredDevices: content.buildDiscovered()
                priority: root.devicePriority
                onToggleRequested: BluetoothService.toggle()
                onScanRequested: BluetoothService.discovering ? BluetoothService.stopDiscovery() : BluetoothService.startDiscovery()
                onDisconnectRequested: function (mac) { BluetoothService.disconnectDevice(mac); }
                onPairRequested: function (mac) { BluetoothService.pairDevice(mac); }
            }
        }
    }
}
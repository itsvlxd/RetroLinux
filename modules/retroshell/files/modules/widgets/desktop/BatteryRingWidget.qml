import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config
import qs.modules.widgets.desktop

// Desktop battery rings widget — shows the host battery + connected Bluetooth
// devices as Apple-style rings. 2x2 (single) or 2x4 (up to 4 devices).
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0
    cardBorder: false

    property bool wide: false

    readonly property var hiddenDevices: (root.widgetData && root.widgetData.hiddenDevices)
        ? root.widgetData.hiddenDevices : []

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

            function buildDevices() {
                var out = [];
                if (Battery.available && root.hiddenDevices.indexOf("host") === -1) {
                    out.push({
                        id: "host",
                        name: "Laptop",
                        type: "laptop",
                        battery: Battery.percentage,
                        isCharging: Battery.isCharging,
                        isConnected: true
                    });
                }
                var list = BluetoothService.friendlyDeviceList;
                var max = root.wide ? 4 : 1;
                for (var i = 0; i < list.length && out.length < max; i++) {
                    var d = list[i];
                    if (d && d.connected && d.battery >= 0
                            && root.hiddenDevices.indexOf(d.address) === -1) {
                        out.push({
                            id: d.address,
                            name: d.name,
                            type: content.typeOf(d.icon),
                            battery: d.battery,
                            isCharging: false,
                            isConnected: true
                        });
                    }
                }
                return out;
            }

            BatteryRingCard {
                anchors.fill: parent
                wide: root.wide
                devices: content.buildDevices()
            }
        }
    }
}
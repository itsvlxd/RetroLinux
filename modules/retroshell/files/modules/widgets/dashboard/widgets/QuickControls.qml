import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config
import "../controls"

StyledRect {
    id: root
    variant: "pane"
    Layout.alignment: Qt.AlignHCenter
    implicitWidth: internalBgRect.implicitWidth + 8
    implicitHeight: columnLayout.implicitHeight + 8
    radius: Styling.radius(4)
    
    property int expandedPanel: -1 // -1: none, 0: wifi, 1: bluetooth, 2: quickshare, 3: caffeine
    property bool darkMode: true
    property bool dlLocked: false

    property var controlOrder: (Config.dashboard && Config.dashboard.controlOrder)
        ? Config.dashboard.controlOrder
        : ["wifi", "bluetooth", "quickshare", "caffeine", "darkmode", "nightlight"]

    function controlComponentFor(id) {
        switch (id) {
        case "wifi": return wifiComponent;
        case "bluetooth": return bluetoothComponent;
        case "quickshare": return quickshareComponent;
        case "caffeine": return caffeineComponent;
        case "darkmode": return darkModeComponent;
        case "nightlight": return nightLightComponent;
        }
        return undefined;
    }

    Process { id: dlProc; running: false; stdout: SplitParser {} }
    Timer { id: dlUnlock; interval: 3000; repeat: false; onTriggered: dlLocked = false }

    Process { id: modeReadProc; running: false
        stdout: StdioCollector {
            onStreamFinished: { darkMode = text.trim() !== "light"; }
        }
    }

    Component.onCompleted: {
        var cfg = Quickshell.env("RETRO_CONFIG") || Quickshell.env("HOME") + "/.config/retro";
        modeReadProc.command = ["bash", "-c", "source '" + cfg + "/variables.sh' 2>/dev/null; echo $RETRO_THEME_MODE"];
        modeReadProc.running = true;
    }
    
    onVisibleChanged: {
        if (!visible) {
            root.expandedPanel = -1;
        } else {
            BluetoothService.initialize();
            QuickShareService.refresh();
        }
    }
    
    Behavior on implicitHeight {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutCubic
        }
    }

    ColumnLayout {
        id: columnLayout
        anchors.fill: parent
        anchors.margins: 4
        spacing: 0
        
        StyledRect {
            id: internalBgRect
            variant: "internalbg"
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 5 * 48 + 4 * 4 + 8
            implicitHeight: 48 + 8
            radius: Styling.radius(0)

            ScrollView {
                id: buttonScroll
                anchors.fill: parent
                anchors.margins: 4
                clip: true
                contentWidth: buttonRow.width
                contentHeight: buttonRow.height
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                RowLayout {
                    id: buttonRow
                    width: buttonRow.implicitWidth
                    height: 48
                    spacing: 4

                Repeater {
                    model: root.controlOrder

                    Loader {
                        required property string modelData
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        sourceComponent: root.controlComponentFor(modelData)
                    }
                }
                }
            }
        }
        
        Item {
            id: panelArea
            Layout.fillWidth: true
            Layout.preferredHeight: {
                if (root.expandedPanel === -1) return 0;
                if (root.expandedPanel === 3) return 120;
                return 280;
            }
            clip: true
            opacity: root.expandedPanel !== -1 ? 1 : 0
            
            Behavior on Layout.preferredHeight {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
            }
            
            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
            }
            
            StyledRect {
                variant: "internalbg"
                anchors.fill: parent
                anchors.margins: 4
                radius: Styling.radius(0)
                clip: true

                Item {
                    id: panelStack
                    anchors.fill: parent
                    anchors.margins: 8 // Extra margin for content
                    
                    Loader {
                        id: wifiLoader
                        anchors.fill: parent
                        active: root.expandedPanel === 0
                        source: "../controls/WifiPanel.qml"
                        asynchronous: true
                        
                        opacity: root.expandedPanel === 0 ? 1 : 0
                        x: root.expandedPanel === 0 ? 0 : (root.expandedPanel === 1 ? -width : width)
                        
                        onLoaded: {
                            if (item) {
                                item.maxContentWidth = width;
                            }
                        }

                        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart } }
                        Behavior on x { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart } }
                    }

                    Loader {
                        id: bluetoothLoader
                        anchors.fill: parent
                        active: root.expandedPanel === 1
                        source: "../controls/BluetoothPanel.qml"
                        asynchronous: true
                        
                        opacity: root.expandedPanel === 1 ? 1 : 0
                        x: root.expandedPanel === 1 ? 0 : (root.expandedPanel === 0 ? width : -width)
                        
                        onLoaded: {
                            if (item) {
                                item.maxContentWidth = width;
                            }
                        }

                        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart } }
                        Behavior on x { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart } }
                    }

                    Loader {
                        id: quickshareLoader
                        anchors.fill: parent
                        active: root.expandedPanel === 2
                        source: "../controls/QuickSharePanel.qml"
                        asynchronous: true
                        
                        opacity: root.expandedPanel === 2 ? 1 : 0
                        x: root.expandedPanel === 2 ? 0 : (root.expandedPanel === 0 ? width : (root.expandedPanel === 1 ? -width : width))
                        
                        onLoaded: {
                            if (item) {
                                item.maxContentWidth = width;
                                item.requestClose.connect(() => { root.expandedPanel = -1; });
                            }
                        }

                        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart } }
                        Behavior on x { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart } }
                    }

                    Loader {
                        id: caffeineLoader
                        anchors.fill: parent
                        active: root.expandedPanel === 3
                        source: "../controls/CaffeinePanel.qml"
                        asynchronous: true

                        opacity: root.expandedPanel === 3 ? 1 : 0
                        x: root.expandedPanel === 3 ? 0 : (root.expandedPanel === 0 ? -width : width)

                        onLoaded: {
                            if (item) {
                                item.maxContentWidth = width;
                                item.requestClose.connect(() => { root.expandedPanel = -1; });
                            }
                        }

                        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart } }
                        Behavior on x { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart } }
                    }
                }
            }
        }
    }
    
    function togglePanel(index) {
        if (root.expandedPanel === index) {
            root.expandedPanel = -1;
        } else {
            root.expandedPanel = index;
        }
    }
    Component {
        id: wifiComponent
        ControlButton {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            iconName: {
                if (!NetworkService.wifiEnabled)
                    return Icons.wifiOff;
                const strength = NetworkService.networkStrength;
                if (strength === 0)
                    return Icons.wifiHigh;
                if (strength < 25)
                    return Icons.wifiNone;
                if (strength < 50)
                    return Icons.wifiLow;
                if (strength < 75)
                    return Icons.wifiMedium;
                return Icons.wifiHigh;
            }
            isActive: NetworkService.wifiEnabled || root.expandedPanel === 0
            tooltipText: NetworkService.wifiEnabled ? "Wi-Fi: On" : "Wi-Fi: Off"
            onClicked: NetworkService.toggleWifi()
            onRightClicked: root.togglePanel(0)
            onLongPressed: root.togglePanel(0)
        }
    }

    Component {
        id: bluetoothComponent
        ControlButton {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            iconName: {
                if (!BluetoothService.enabled)
                    return Icons.bluetoothOff;
                if (BluetoothService.connected)
                    return Icons.bluetoothConnected;
                return Icons.bluetooth;
            }
            isActive: BluetoothService.enabled || root.expandedPanel === 1
            tooltipText: {
                if (!BluetoothService.enabled)
                    return "Bluetooth: Off";
                if (BluetoothService.connected)
                    return "Bluetooth: Connected";
                return "Bluetooth: On";
            }
            onClicked: BluetoothService.toggle()
            onRightClicked: root.togglePanel(1)
            onLongPressed: root.togglePanel(1)
        }
    }

    Component {
        id: quickshareComponent
        ControlButton {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            visible: Config.notch.quickshareEnabled
            iconName: Icons.quickshare
            isActive: QuickShareService.running
            tooltipText: QuickShareService.running ? "Quick Share: On" : "Quick Share: Off"
            onClicked: QuickShareService.toggle()
            onRightClicked: root.togglePanel(2)
            onLongPressed: root.togglePanel(2)
        }
    }

    Component {
        id: caffeineComponent
        ControlButton {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            iconName: Icons.caffeine
            isActive: CaffeineService.inhibit
            activeVariant: CaffeineService.timedMinutes > 0 ? "bg" : "primary"
            activeHoverVariant: CaffeineService.timedMinutes > 0 ? "focus" : "primaryfocus"
            tooltipText: CaffeineService.inhibit ? "Caffeine: On" : "Caffeine: Off"
            onClicked: CaffeineService.toggleInhibit()
            onRightClicked: root.togglePanel(3)
            onLongPressed: root.togglePanel(3)

            Item {
                anchors.fill: parent
                clip: true
                z: -1
                visible: CaffeineService.inhibit && CaffeineService.timedMinutes > 0

                Rectangle {
                    id: caffeineFill
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height * (CaffeineService.totalSecondsRemaining / Math.max(1, CaffeineService.initialMinutes * 60))
                    color: Styling.srItem("overprimary")
                    opacity: 0.35

                    Behavior on height {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: 1000
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                WavyLine {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: {
                        var ratio = CaffeineService.totalSecondsRemaining / Math.max(1, CaffeineService.initialMinutes * 60);
                        return parent.height * (1 - ratio) - height / 2;
                    }
                    height: 10
                    color: Styling.srItem("overprimary")
                    lineWidth: 2
                    amplitudeMultiplier: 0.5
                    frequency: 3
                    running: CaffeineService.timedMinutes > 0
                }
            }
        }
    }

    Component {
        id: darkModeComponent
        ControlButton {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            iconName: root.darkMode ? Icons.nightLight : Icons.sun
            isActive: root.darkMode
            tooltipText: root.darkMode ? "Dark Mode" : "Light Mode"
            onClicked: {
                if (root.dlLocked) return;
                root.dlLocked = true;
                root.darkMode = !root.darkMode;
                var rd = Quickshell.env("RETRO_DIR");
                dlProc.command = ["bash", rd + "/scripts/theme_core.sh", "--mode", root.darkMode ? "dark" : "light"];
                dlProc.running = true;
                root.dlUnlock.start();
            }
        }
    }

    Component {
        id: nightLightComponent
        ControlButton {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            iconName: Icons.lightbulb
            isActive: NightLightService.active
            tooltipText: NightLightService.active ? "Night Light: On" : "Night Light: Off"
            onClicked: NightLightService.toggle()
        }
    }

}

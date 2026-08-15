pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Services.UPower
import qs.modules.theme
import qs.config

Singleton {
    id: root

    readonly property UPowerDevice primaryDevice: UPower.displayDevice

    readonly property bool available: primaryDevice !== null && primaryDevice.type === UPowerDevice.Battery
    readonly property real percentage: available ? (primaryDevice.percentage * 100) : 0
    readonly property bool isCharging: available && primaryDevice.state === UPowerDevice.Charging
    readonly property bool isPluggedIn: available && (primaryDevice.state === UPowerDevice.Charging || primaryDevice.state === UPowerDevice.FullyCharged)
    readonly property int chargeState: available ? primaryDevice.state : UPowerDevice.Unknown

    // Add some helpful descriptive properties if needed
    readonly property string timeToEmpty: available && primaryDevice.timeToEmpty > 0 ? formatTime(primaryDevice.timeToEmpty) : ""
    readonly property string timeToFull: available && primaryDevice.timeToFull > 0 ? formatTime(primaryDevice.timeToFull) : ""

    function formatTime(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    function getBatteryIcon(horizontal) {
        if (!available) return Icons.plug;

        if (isPluggedIn) return horizontal ? Icons.batteryHCharging : Icons.batteryCharging;

        const pct = percentage;
        if (pct > 75) return horizontal ? Icons.batteryHFull : Icons.batteryFull;
        if (pct > 50) return horizontal ? Icons.batteryHHigh : Icons.batteryHigh;
        if (pct > 25) return horizontal ? Icons.batteryHMedium : Icons.batteryMedium;
        if (pct > 5) return horizontal ? Icons.batteryHLow : Icons.batteryLow;
        return horizontal ? Icons.batteryHEmpty : Icons.batteryEmpty;
    }
}

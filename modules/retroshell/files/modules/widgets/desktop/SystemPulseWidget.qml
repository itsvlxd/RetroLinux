import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config
import qs.modules.widgets.desktop

// Desktop system monitor widget — 2x4 (320x160).
WidgetHost {
    id: root

    implicitWidth: 320
    implicitHeight: 160
    contentMargins: 0

    readonly property bool showCpu: (root.widgetData && root.widgetData.showCpu !== undefined)
        ? root.widgetData.showCpu === true : true
    readonly property bool showGpu: (root.widgetData && root.widgetData.showGpu !== undefined)
        ? root.widgetData.showGpu === true : true
    readonly property bool showRam: (root.widgetData && root.widgetData.showRam !== undefined)
        ? root.widgetData.showRam === true : true
    readonly property bool showDisk: (root.widgetData && root.widgetData.showDisk !== undefined)
        ? root.widgetData.showDisk === true : false
    readonly property bool showCpuTemp: (root.widgetData && root.widgetData.showCpuTemp !== undefined)
        ? root.widgetData.showCpuTemp === true : true
    readonly property bool showGpuTemp: (root.widgetData && root.widgetData.showGpuTemp !== undefined)
        ? root.widgetData.showGpuTemp === true : true
    readonly property bool showDiskTemp: (root.widgetData && root.widgetData.showDiskTemp !== undefined)
        ? root.widgetData.showDiskTemp === true : false

    readonly property string diskLabel: SystemResources.validDisks.length > 0 ? SystemResources.validDisks[0] : "/"

    contentComponent: Component {
        Item {
            anchors.fill: parent

            SystemPulseCard {
                anchors.fill: parent

                cpuUsage: SystemResources.cpuUsage
                cpuTemp: SystemResources.cpuTemp
                gpuUsage: SystemResources.gpuUsage
                gpuTemp: SystemResources.gpuTemp
                ramUsage: SystemResources.ramUsage
                diskUsage: SystemResources.diskUsage[root.diskLabel] !== undefined ? SystemResources.diskUsage[root.diskLabel] : 0
                diskTemp: SystemResources.diskTemp

                cpuHistory: SystemResources.cpuHistory
                gpuHistory: SystemResources.gpuHistories.length > 0 ? SystemResources.gpuHistories[0] : []
                ramHistory: SystemResources.ramHistory
                cpuTempHistory: SystemResources.cpuTempHistory
                gpuTempHistory: SystemResources.gpuTempHistories.length > 0 ? SystemResources.gpuTempHistories[0] : []
                diskTempHistory: SystemResources.diskTempHistory

                showCpu: root.showCpu
                showGpu: root.showGpu
                showRam: root.showRam
                showDisk: root.showDisk
                showCpuTemp: root.showCpuTemp
                showGpuTemp: root.showGpuTemp
                showDiskTemp: root.showDiskTemp
            }
        }
    }
}

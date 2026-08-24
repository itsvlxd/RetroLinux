import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config
import qs.modules.widgets.desktop

// Desktop system monitor — 2x2 (160x160) card showing CPU, RAM and disk usage.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            readonly property string diskLabel: SystemResources.validDisks.length > 0 ? SystemResources.validDisks[0] : "/"

            // Card background
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Colors.surfaceContainer }
                    GradientStop { position: 1.0; color: Colors.surfaceContainerLow }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 7

                // CPU
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: Icons.cpu
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: Colors.outline
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "CPU"
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Text {
                        text: Math.round(SystemResources.cpuUsage) + "%"
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Item {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 6
                        Rectangle {
                            anchors.fill: parent
                            radius: 3
                            color: Colors.surfaceContainerHighest
                        }
                        Rectangle {
                            width: parent.width * (SystemResources.cpuUsage / 100)
                            height: parent.height
                            radius: 3
                            color: Colors.primary
                        }
                    }
                }

                // RAM
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: Icons.ram
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: Colors.outline
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "RAM"
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Text {
                        text: Math.round(SystemResources.ramUsage) + "%"
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Item {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 6
                        Rectangle {
                            anchors.fill: parent
                            radius: 3
                            color: Colors.surfaceContainerHighest
                        }
                        Rectangle {
                            width: parent.width * (SystemResources.ramUsage / 100)
                            height: parent.height
                            radius: 3
                            color: Colors.primary
                        }
                    }
                }

                // Disk
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: Icons.disk
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: Colors.outline
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Disk"
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Text {
                        text: (SystemResources.diskUsage[content.diskLabel] !== undefined
                               ? Math.round(SystemResources.diskUsage[content.diskLabel])
                               : 0) + "%"
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    Item {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 6
                        Rectangle {
                            anchors.fill: parent
                            radius: 3
                            color: Colors.surfaceContainerHighest
                        }
                        Rectangle {
                            width: parent.width * (SystemResources.diskUsage[content.diskLabel] !== undefined
                                                   ? SystemResources.diskUsage[content.diskLabel] : 0) / 100
                            height: parent.height
                            radius: 3
                            color: Colors.tertiary
                        }
                    }
                }
            }
        }
    }
}
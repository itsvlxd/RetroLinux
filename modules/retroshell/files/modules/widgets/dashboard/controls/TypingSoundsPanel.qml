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

    signal requestClose()

    implicitWidth: Math.min(parent ? parent.width : 0, maxContentWidth)
    implicitHeight: contentColumn.implicitHeight

    ColumnLayout {
        id: contentColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        PanelTitlebar {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            title: "Typing Sounds"
            statusText: {
                if (TypingSoundsService.isPreparing) return "Preparing...";
                if (TypingSoundsService.inputToolMissing) return "Missing " + TypingSoundsService.requiredTool;
                if (TypingSoundsService.notInInputGroup) return "Not in input group";
                return TypingSoundsService.enabled ? "Enabled" : "Disabled";
            }
            statusColor: {
                if (TypingSoundsService.inputToolMissing || TypingSoundsService.notInInputGroup)
                    return Colors.warning;
                return TypingSoundsService.enabled ? Styling.srItem("overprimary") : Colors.outline;
            }
            showToggle: true
            toggleChecked: TypingSoundsService.enabled

            onToggleChanged: checked => {
                TypingSoundsService.saveSetting("enabled", checked);
            }
        }

        StyledRect {
            Layout.fillWidth: true
            visible: TypingSoundsService.inputToolMissing || TypingSoundsService.notInInputGroup
            variant: "common"
            enableShadow: false
            radius: Styling.radius(0)

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                text: {
                    if (TypingSoundsService.notInInputGroup)
                        return "Add user to input group: sudo usermod -aG input $USER";
                    if (TypingSoundsService.inputToolMissing)
                        return "Install " + TypingSoundsService.requiredTool + " to use typing sounds";
                    return "";
                }
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.warning
                wrapMode: Text.WordWrap
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            variant: "common"
            enableShadow: false
            radius: Styling.radius(0)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: Icons.speakerHigh
                    font.family: Icons.font
                    font.pixelSize: 14
                    color: Colors.primary
                }

                Slider {
                    id: volumeSlider
                    Layout.fillWidth: true
                    from: 0
                    to: 200
                    stepSize: 1
                    value: TypingSoundsService.volume
                    onMoved: TypingSoundsService.saveSetting("volume", Math.round(value))

                    background: Rectangle {
                        x: volumeSlider.leftPadding
                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                        implicitWidth: 200
                        implicitHeight: 4
                        width: volumeSlider.availableWidth
                        height: implicitHeight
                        radius: 2
                        color: Colors.outlineVariant

                        Rectangle {
                            width: volumeSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 2
                            color: Colors.primary
                        }
                    }

                    handle: Rectangle {
                        x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                        implicitWidth: 14
                        implicitHeight: 14
                        radius: width / 2
                        color: Colors.primary
                    }
                }

                Text {
                    text: Math.round(volumeSlider.value) + "%"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    font.bold: true
                    color: Colors.overBackground
                    Layout.preferredWidth: 32
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: packAndDeviceColumn.implicitHeight + 16
            variant: "common"
            enableShadow: false
            radius: Styling.radius(0)

            ColumnLayout {
                id: packAndDeviceColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Sound Pack"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        font.bold: true
                        color: Colors.overBackground
                        horizontalAlignment: Text.AlignLeft
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: Icons.note
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: Colors.primary
                        }

                        StyledCombo {
                            id: packCombo
                            Layout.fillWidth: true
                            model: TypingSoundsService.availablePacks.map(p => p.name)
                            currentIndex: {
                                var packs = TypingSoundsService.availablePacks;
                                for (var i = 0; i < packs.length; i++) {
                                    if (packs[i].id === TypingSoundsService.selectedPackId)
                                        return i;
                                }
                                return 0;
                            }
                            onActivated: index => {
                                var packs = TypingSoundsService.availablePacks;
                                if (index >= 0 && index < packs.length)
                                    TypingSoundsService.saveSetting("selectedPackId", packs[index].id);
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Keyboard Device"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        font.bold: true
                        color: Colors.overBackground
                        horizontalAlignment: Text.AlignLeft
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: Icons.keyboard
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: Colors.primary
                        }

                        StyledCombo {
                            id: deviceCombo
                            Layout.fillWidth: true
                            model: TypingSoundsService.availableDevices.map(d => d.label)
                            currentIndex: {
                                var devs = TypingSoundsService.availableDevices;
                                for (var i = 0; i < devs.length; i++) {
                                    if (devs[i].value === TypingSoundsService.selectedDevicePath)
                                        return i;
                                }
                                return 0;
                            }
                            onActivated: index => {
                                var devs = TypingSoundsService.availableDevices;
                                if (index >= 0 && index < devs.length)
                                    TypingSoundsService.saveSetting("selectedDevicePath", devs[index].value);
                            }
                        }
                    }
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            variant: "common"
            enableShadow: false
            radius: Styling.radius(0)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: Icons.mouse
                    font.family: Icons.font
                    font.pixelSize: 14
                    color: Colors.primary
                }

                Text {
                    text: "Mouse Clicks"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overBackground
                    Layout.fillWidth: true
                }

                Switch {
                    id: mouseSwitch
                    checked: TypingSoundsService.mouseEnabled
                    onCheckedChanged: TypingSoundsService.saveSetting("mouseEnabled", checked)

                    indicator: Rectangle {
                        implicitWidth: 36
                        implicitHeight: 18
                        x: mouseSwitch.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: height / 2
                        color: mouseSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                        border.color: mouseSwitch.checked ? Styling.srItem("overprimary") : Colors.outline

                        Rectangle {
                            x: mouseSwitch.checked ? parent.width - width - 2 : 2
                            y: 2
                            width: parent.height - 4
                            height: width
                            radius: width / 2
                            color: mouseSwitch.checked ? Colors.background : Colors.overSurfaceVariant
                        }
                    }
                    background: null
                }
            }
        }

    }
}

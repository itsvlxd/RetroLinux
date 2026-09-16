import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config
import qs.modules.widgets.desktop
import qs.modules.widgets.dashboard.widgets

// Desktop weather widget — animated weather scene + 7-day forecast card.
WidgetHost {
    id: root

    implicitWidth: 320
    implicitHeight: 240

    contentComponent: Component {
        ColumnLayout {
            anchors.fill: parent
            spacing: 4

            WeatherWidget {
                id: scene
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                showDebugControls: false
                animationsEnabled: true
            }

            // 7-day forecast row
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: WeatherService.dataAvailable && WeatherService.forecast.length > 0

                StyledRect {
                    id: forecastCard
                    variant: "pane"
                    anchors.fill: parent
                    radius: Styling.radius(2)

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Repeater {
                            model: WeatherService.forecast.slice(0, 5)

                            Row {
                                id: fdayRow
                                required property var modelData
                                required property int index
                                spacing: 4

                                Column {
                                    spacing: 1
                                    width: (scene.width - 12 - (4 * 4) - (4 * 6)) / 5

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: fdayRow.modelData.dayName
                                        color: Colors.overBackground
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-2)
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: fdayRow.modelData.emoji
                                        font.family: Config.emojiFont
                                        font.pixelSize: Styling.fontSize(2)
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: (Math.round(fdayRow.modelData.maxTemp) >= 0 ? "+" : "") + Math.round(fdayRow.modelData.maxTemp) + "\u00B0"
                                        color: Colors.overBackground
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-2)
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: (Math.round(fdayRow.modelData.minTemp) >= 0 ? "+" : "") + Math.round(fdayRow.modelData.minTemp) + "\u00B0"
                                        color: Colors.outline
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-2)
                                        font.weight: Font.Normal
                                    }
                                }

                                Separator {
                                    vert: true
                                    visible: fdayRow.index < 4
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

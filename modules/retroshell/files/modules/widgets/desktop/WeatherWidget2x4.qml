import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config
import qs.modules.widgets.desktop
import qs.modules.widgets.dashboard.widgets

// Desktop weather widget — wide (2x4) card, 320x160. Animated weather scene
// fills the whole card; an entire-week forecast strip overlays the bottom.
WidgetHost {
    id: root

    implicitWidth: 320
    implicitHeight: 160
    contentMargins: 0

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            // Animated weather scene filling the whole card
            WeatherWidget {
                anchors.fill: parent
                showDebugControls: false
                animationsEnabled: true
            }

            // Bottom fade so the forecast reads over the scene
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 66
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.4) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.62) }
                }
            }

            // Entire-week forecast strip (7 days)
            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                spacing: 2

                Repeater {
                    model: WeatherService.dataAvailable ? WeatherService.forecast : []

                    Item {
                        required property var modelData
                        required property int index

                        width: (parent.width - (7 - 1) * 2) / 7
                        height: 56

                        Column {
                            anchors.fill: parent
                            anchors.topMargin: 4
                            spacing: 1

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.dayName
                                color: Qt.rgba(1, 1, 1, 0.85)
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-3)
                                layer.enabled: true
                                layer.effect: BgShadow {}
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.emoji
                                font.family: Config.emojiFont
                                font.pixelSize: Styling.fontSize(1)
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(modelData.maxTemp) + "°"
                                color: "#ffffff"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-3)
                                font.weight: Font.Bold
                                layer.enabled: true
                                layer.effect: BgShadow {}
                            }
                        }
                    }
                }
            }
        }
    }
}
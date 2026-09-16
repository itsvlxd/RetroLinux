import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

StyledRect {
    id: lockWeather
    variant: "bg"

    readonly property bool hasWeather: WeatherService.dataAvailable
    readonly property string location: {
        var loc = Config.weather.location || "";
        if (loc.match(/^-?\d+\.\d+,-?\d+\.\d+$/)) return "";
        return loc;
    }

    readonly property real mainRowHeight: 56
    readonly property real totalHeight: mainRowHeight + (hasWeather && WeatherService.forecast.length > 0 ? forecastRow.implicitHeight + 16 : 0)

    visible: hasWeather
    height: totalHeight
    radius: Config.roundness > 0 ? (mainRowHeight / 2) * (Config.roundness / 16) : 0
    backgroundOpacity: 0.0

    // ── Time-of-day gradient (from WeatherWidget) ──
    readonly property color dayTop: "#87CEEB"
    readonly property color dayMid: "#B0E0E6"
    readonly property color dayBot: "#E0F6FF"
    readonly property color eveningTop: "#1a1a2e"
    readonly property color eveningMid: "#e94560"
    readonly property color eveningBot: "#ffeaa7"
    readonly property color nightTop: "#0f0f23"
    readonly property color nightMid: "#1a1a3a"
    readonly property color nightBot: "#2d2d5a"

    readonly property var blend: WeatherService.effectiveTimeBlend

    function blendColors(c1, c2, c3, b) {
        var r = c1.r * b.day + c2.r * b.evening + c3.r * b.night;
        var g = c1.g * b.day + c2.g * b.evening + c3.g * b.night;
        var bv = c1.b * b.day + c2.b * b.evening + c3.b * b.night;
        return Qt.rgba(r, g, bv, 1.0);
    }

    readonly property color topColor: blendColors(dayTop, eveningTop, nightTop, blend)
    readonly property color midColor: blendColors(dayMid, eveningMid, nightMid, blend)
    readonly property color botColor: blendColors(dayBot, eveningBot, nightBot, blend)

    // ── Weather effect ──
    readonly property string weatherEffect: WeatherService.effectiveWeatherEffect
    readonly property real weatherIntensity: WeatherService.effectiveWeatherIntensity
    readonly property bool isOvercast: weatherEffect === "clouds" || weatherEffect === "rain" || weatherEffect === "drizzle" || weatherEffect === "snow" || weatherEffect === "thunderstorm" || weatherEffect === "fog"

    // ── Gradient background ──
    Rectangle {
        id: gradBg
        anchors.fill: parent; radius: lockWeather.radius; clip: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: lockWeather.topColor }
            GradientStop { position: 0.5; color: lockWeather.midColor }
            GradientStop { position: 1.0; color: lockWeather.botColor }
        }
    }

    // Overcast overlay
    Rectangle {
        anchors.fill: parent; radius: lockWeather.radius; clip: true
        visible: lockWeather.isOvercast
        opacity: lockWeather.weatherIntensity * 0.7
        gradient: Gradient {
            GradientStop { position: 0.0; color: lockWeather.blend.night > 0.5 ? Qt.rgba(0.15,0.15,0.2,0.9) : lockWeather.blend.evening > 0.3 ? Qt.rgba(0.3,0.25,0.3,0.85) : Qt.rgba(0.5,0.52,0.55,0.8) }
            GradientStop { position: 0.6; color: lockWeather.blend.night > 0.5 ? Qt.rgba(0.2,0.2,0.25,0.7) : lockWeather.blend.evening > 0.3 ? Qt.rgba(0.35,0.3,0.35,0.6) : Qt.rgba(0.6,0.62,0.65,0.5) }
            GradientStop { position: 1.0; color: Qt.rgba(0.5,0.5,0.5,0.2) }
        }
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
    }

    // Semi-transparent surface layer for readability
    StyledRect {
        anchors.fill: parent
        variant: "internalbg"
        opacity: 0.25
        radius: lockWeather.radius
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 16; anchors.rightMargin: 16
        anchors.topMargin: 0; anchors.bottomMargin: 8
        spacing: 0

        // Main row
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: lockWeather.mainRowHeight
            spacing: 12

            Text {
                text: WeatherService.weatherSymbol
                font.pixelSize: 24; font.family: Config.emojiFont
                color: Colors.overBackground
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: Math.round(WeatherService.currentTemp) + "°" + Config.weather.unit
                font.pixelSize: Config.theme.fontSize; font.weight: Font.Bold
                font.family: Config.theme.font; color: Colors.overBackground
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                Layout.fillWidth: true
                text: lockWeather.location
                font.pixelSize: Config.theme.fontSize; font.family: Config.theme.font
                font.weight: Font.Medium; color: Colors.overBackground; opacity: 0.8
                elide: Text.ElideRight; maximumLineCount: 1
                Layout.alignment: Qt.AlignVCenter
                visible: text.length > 0
            }
        }

        // Divider
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 1
            color: Colors.outlineVariant; opacity: 0.3
            visible: WeatherService.forecast.length > 0
        }

        // Forecast row (always visible)
        Row {
            id: forecastRow
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: WeatherService.forecast.length > 0
            spacing: 0

            Repeater {
                model: WeatherService.forecast.slice(0, 5)
                delegate: Item {
                    id: fItem
                    required property var modelData
                    required property int index
                    width: forecastRow.width / 5
                    height: fDay.implicitHeight

                    Column {
                        id: fDay
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: fItem.modelData.dayName || ""
                            color: Colors.overBackground; opacity: 0.6
                            font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-2)
                            font.weight: Font.Medium
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: fItem.modelData.emoji || ""
                            font.family: Config.emojiFont
                            font.pixelSize: Styling.fontSize(2)
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(fItem.modelData.maxTemp) + "°"
                            color: Colors.overBackground
                            font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-2)
                            font.weight: Font.Bold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(fItem.modelData.minTemp) + "°"
                            color: Colors.outline
                            font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-2)
                        }
                    }

                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 1; height: Math.min(fDay.implicitHeight - 8, fItem.height - 8)
                        color: Colors.outlineVariant; opacity: 0.3
                        visible: fItem.index < 4
                    }
                }
            }
        }
    }
}

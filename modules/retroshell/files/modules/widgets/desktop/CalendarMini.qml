import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.config
import "layout.js" as CalendarLayout

// Month calendar styled exactly like the Clock.qml mini calendar: a month
// header in the outline color, day-of-week abbreviations, and day numbers in
// circles (today = primary fill). Scales to fill any size it is given.
Item {
    id: root

    property int monthShift: 0
    property date currentDate: new Date()
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift, currentDate)
    property var layoutData: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    property var calendar: layoutData.calendar
    property int currentDayOfWeek: (monthShift !== 0) ? -1 : (currentDate.getDay() + 6) % 7

    readonly property real headerH: Math.max(16, Math.min(26, height * 0.12))
    readonly property real cellW: width / 7
    readonly property real cellH: Math.max(11, (height - headerH - 4) / 7)
    readonly property real circle: Math.min(cellW, cellH) - 2
    readonly property real dayFont: Math.max(7, circle * 0.45)
    readonly property real headerFont: Math.max(9, Math.min(width * 0.06, headerH * 0.6))

    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.currentDate = new Date()
    }

    function getDayAbbrev(dayIndex) {
        var d = new Date(2024, 0, 1 + dayIndex);
        var dayName = d.toLocaleDateString(Qt.locale(), "ddd");
        return (dayName.charAt(0).toUpperCase() + dayName.slice(1, 2)).replace(".", "");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 2

        // Month header (Clock.qml style)
        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerH
            text: root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
            color: Colors.outline
            font.family: Config.theme.font
            font.pixelSize: root.headerFont
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        // Day-of-week abbreviations
        Row {
            Layout.fillWidth: true
            Layout.preferredHeight: root.cellH
            Repeater {
                model: 7
                delegate: Item {
                    required property int index
                    width: root.cellW
                    height: root.cellH
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.getDayAbbrev(index)
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: root.dayFont
                        font.weight: Font.Medium
                    }
                }
            }
        }

        // 6 day rows
        Repeater {
            model: 6
            delegate: Item {
                id: rowItem
                required property int index
                width: root.width
                height: root.cellH

                Row {
                    anchors.fill: parent
                    Repeater {
                        model: 7
                        delegate: Item {
                            required property int index
                            readonly property var info: root.calendar[rowItem.index][index]
                            readonly property bool isToday: info.today === 1
                            readonly property bool isDim: info.today === -1

                            width: root.cellW
                            height: root.cellH

                            // Day circle (today = primary fill)
                            Rectangle {
                                anchors.centerIn: parent
                                width: root.circle
                                height: root.circle
                                radius: width / 2
                                color: isToday ? Styling.srItem("overprimary") : "transparent"
                            }

                            Text {
                                anchors.centerIn: parent
                                text: info.day
                                color: isToday ? Colors.background : Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: root.dayFont
                                font.weight: isToday ? Font.Bold : Font.Normal
                                opacity: isDim ? 0.35 : 1.0
                            }
                        }
                    }
                }
            }
        }
    }
}
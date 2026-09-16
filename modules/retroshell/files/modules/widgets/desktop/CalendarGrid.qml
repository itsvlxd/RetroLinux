import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.config
import "layout.js" as CalendarLayout

// Adaptive month calendar that fills its parent and scales the day cells to
// whatever size it is given (used by the desktop calendar widgets).
Item {
    id: root

    property int monthShift: 0
    property date currentDate: new Date()
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift, currentDate)
    property var layoutData: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    property var calendar: layoutData.calendar
    property int currentWeekRow: layoutData.currentWeekRow
    property int currentDayOfWeek: (monthShift !== 0) ? -1 : (currentDate.getDay() + 6) % 7

    readonly property real headerH: Math.max(20, Math.min(32, height * 0.14))
    readonly property real cellW: width / 7
    readonly property real cellH: Math.max(11, (height - headerH - 6) / 7)
    readonly property real dayFontSize: Math.max(7, Math.min(cellW, cellH) * 0.4)
    readonly property real headerFontSize: Math.max(9, Math.min(width * 0.06, headerH * 0.5))

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
        spacing: 3

        // Header: prev / month title / next
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerH
            spacing: 4

            StyledRect {
                Layout.preferredWidth: root.headerH
                Layout.fillHeight: true
                radius: Styling.radius(0)
                variant: prevMouse.pressed ? "primary" : (prevMouse.containsMouse ? "focus" : "internalbg")
                Text {
                    anchors.centerIn: parent
                    text: Icons.caretLeft
                    font.family: Icons.font
                    font.pixelSize: root.dayFontSize
                    color: Styling.srItem("overprimary")
                }
                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.monthShift--
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Styling.radius(0)
                variant: "internalbg"
                Text {
                    anchors.centerIn: parent
                    text: root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                    font.family: Config.theme.font
                    font.pixelSize: root.headerFontSize
                    font.weight: Font.Bold
                    color: Styling.srItem("overprimary")
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }

            StyledRect {
                Layout.preferredWidth: root.headerH
                Layout.fillHeight: true
                radius: Styling.radius(0)
                variant: nextMouse.pressed ? "primary" : (nextMouse.containsMouse ? "focus" : "internalbg")
                Text {
                    anchors.centerIn: parent
                    text: Icons.caretRight
                    font.family: Icons.font
                    font.pixelSize: root.dayFontSize
                    color: Styling.srItem("overprimary")
                }
                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.monthShift++
                }
            }
        }

        // Day-of-week header
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
                        anchors.centerIn: parent
                        text: root.getDayAbbrev(index)
                        font.family: Config.theme.font
                        font.pixelSize: root.dayFontSize
                        font.weight: Font.Bold
                        color: (index === root.currentDayOfWeek) ? Styling.srItem("overprimary") : Colors.outline
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
                            readonly property bool isWeekRow: rowItem.index === root.currentWeekRow

                            width: root.cellW
                            height: root.cellH

                            // current-week-row background
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Math.max(2, root.cellW * 0.18)
                                color: isWeekRow && !isDim ? Colors.surfaceContainerLow : "transparent"
                            }

                            // today highlight circle
                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.min(root.cellW, root.cellH) - 2
                                height: width
                                radius: width / 2
                                color: isToday ? Colors.primary : "transparent"
                            }

                            Text {
                                anchors.centerIn: parent
                                text: info.day
                                font.family: Config.theme.font
                                font.pixelSize: root.dayFontSize
                                font.weight: (isToday || isWeekRow) ? Font.Bold : Font.Normal
                                opacity: isDim ? 0.35 : 1.0
                                color: isToday ? Colors.overPrimary : Colors.overSurface
                            }
                        }
                    }
                }
            }
        }
    }
}
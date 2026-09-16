import QtQuick
import qs.modules.widgets.desktop

// Desktop calendar widget — small square (2x2) card, 160x160.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160

    contentComponent: Component {
        CalendarGrid {}
    }
}
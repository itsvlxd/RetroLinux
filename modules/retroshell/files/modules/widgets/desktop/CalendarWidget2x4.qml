import QtQuick
import qs.modules.widgets.desktop

// Desktop calendar widget — wide (2x4) card, 320x160.
WidgetHost {
    id: root

    implicitWidth: 320
    implicitHeight: 160

    contentComponent: Component {
        CalendarGrid {}
    }
}
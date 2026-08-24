import QtQuick
import qs.modules.widgets.desktop

// Desktop calendar widget — large square (4x4) card, 320x320.
WidgetHost {
    id: root

    implicitWidth: 320
    implicitHeight: 320

    contentComponent: Component {
        CalendarGrid {}
    }
}
import QtQuick
import qs.modules.widgets.desktop
import qs.modules.widgets.dashboard.widgets

// Desktop weather widget — square (2x2) card, 160x160. Just the animated
// weather scene filling the whole card, nothing else.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    contentComponent: Component {
        WeatherWidget {
            anchors.fill: parent
            showDebugControls: false
            animationsEnabled: true
        }
    }
}
import QtQuick
import qs.modules.widgets.desktop

// Desktop calendar widget — adaptive dashboard-style month calendar with
// prev/next buttons. Sizes to whatever the desktop layer assigns it
// (4x4 = 320x320, 2x4 = 320x160).
WidgetHost {
    id: root

    implicitWidth: 320
    implicitHeight: 320

    contentComponent: Component {
        Calendar {}
    }
}
import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.config
import qs.modules.widgets.desktop

// Desktop photo widget — displays a user-chosen image in a StyledRect frame.
// Sizes: 2x2 (160x160), 2x4 (320x160), 4x2 (320x160).
// Border: pane outer → internalbg inner (same pattern as Calendar).
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0
    cardBorder: false

    readonly property string imagePath: (root.widgetData && root.widgetData.imagePath)
        ? String(root.widgetData.imagePath) : ""
    readonly property bool showBorder: (root.widgetData && root.widgetData.showBorder !== undefined)
        ? root.widgetData.showBorder === true : true

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            // With border: pane → internalbg nesting. Without: plain surface.
            StyledRect {
                anchors.fill: parent
                anchors.margins: root.showBorder ? 4 : 0
                variant: root.showBorder ? "pane" : "internalbg"
                radius: Styling.radius(root.showBorder ? 4 : 0)

                StyledRect {
                    anchors.fill: parent
                    anchors.margins: root.showBorder ? 3 : 0
                    variant: "internalbg"
                    radius: Styling.radius(0)
                    clip: true
                    visible: root.showBorder

                    Image {
                        anchors.fill: parent
                        visible: root.imagePath.length > 0
                        source: root.imagePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        asynchronous: true
                        mipmap: true
                    }

                    Column {
                        anchors.centerIn: parent
                        visible: root.imagePath.length === 0
                        spacing: 6

                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            mipmap: true
                            source: Qt.resolvedUrl("../../../../assets/retro/retro-logo.svg")
                            opacity: 0.2
                            sourceSize.width: 48
                            sourceSize.height: 48
                            fillMode: Image.PreserveAspectFit
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Photo"
                            color: Qt.rgba(1, 1, 1, 0.3)
                            font.family: Config.theme.font
                            font.pixelSize: 9
                            font.weight: Font.Medium
                        }
                    }
                }

                // Borderless mode: image fills the entire widget.
                Image {
                    anchors.fill: parent
                    visible: !root.showBorder && root.imagePath.length > 0
                    source: root.imagePath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    asynchronous: true
                    mipmap: true
                }

                Column {
                    anchors.centerIn: parent
                    visible: !root.showBorder && root.imagePath.length === 0
                    spacing: 6

                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        mipmap: true
                        source: Qt.resolvedUrl("../../../../assets/retro/retro-logo.svg")
                        opacity: 0.2
                        sourceSize.width: 48
                        sourceSize.height: 48
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Photo"
                        color: Qt.rgba(1, 1, 1, 0.3)
                        font.family: Config.theme.font
                        font.pixelSize: 9
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}

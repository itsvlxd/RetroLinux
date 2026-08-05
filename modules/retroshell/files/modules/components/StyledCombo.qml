import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.config

Item {
    id: root

    property var model: []
    property int currentIndex: 0
    property string label: ""
    property int maxPopupHeight: Math.ceil(2.5 * 36)
    signal activated(int index)

    property bool isOpen: false

    readonly property string currentText: {
        if (!model || model.length === 0 || currentIndex < 0 || currentIndex >= model.length)
            return "";
        var item = model[currentIndex];
        return typeof item === "string" ? item : (item.text || item.name || "");
    }

    implicitHeight: 36

    // currentIndex is read-only from within; parent owns the value via binding

    StyledRect {
        id: trigger
        anchors.fill: parent
        variant: "primary"
        enableBorder: false
        radius: Styling.radius(0)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: root.currentText
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-1)
                color: trigger.item
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: Icons.caretDown
                font.family: Icons.font
                font.pixelSize: 12
                color: trigger.item
                opacity: 0.6
                verticalAlignment: Text.AlignVCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (popup.visible) {
                    popup.close();
                } else {
                    popup.open();
                }
            }
        }
    }

    Popup {
        id: popup
        y: trigger.height
        width: trigger.width
        padding: 4
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape

        onOpened: {
            root.isOpen = true;
            listView.currentIndex = root.currentIndex;
        }

        onClosed: {
            root.isOpen = false;
            listView.currentIndex = root.currentIndex;
        }

        implicitHeight: Math.min(root.model ? root.model.length * 36 : 0, root.maxPopupHeight) + padding * 2

        background: StyledRect {
            variant: "popup"
            enableShadow: true
            radius: Styling.radius(0)
        }

        ListView {
            id: listView
            anchors.fill: parent
            clip: true
            model: root.model
            currentIndex: root.currentIndex
            keyNavigationEnabled: true
            Keys.onUpPressed: {
                if (currentIndex > 0) currentIndex--;
            }
            Keys.onDownPressed: {
                if (currentIndex < root.model.length - 1) currentIndex++;
            }
            Keys.onReturnPressed: select(currentIndex)
            Keys.onEnterPressed: select(currentIndex)
            Keys.onEscapePressed: popup.close()

            highlightFollowsCurrentItem: false

            highlight: Item {
                width: listView.width
                height: 36
                y: listView.currentIndex >= 0 ? listView.currentIndex * 36 : 0

                Behavior on y {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration / 2
                        easing.type: Easing.OutQuart
                    }
                }

                StyledRect {
                    anchors.fill: parent
                    anchors.margins: 4
                    variant: "primary"
                    radius: Styling.radius(0)
                    visible: listView.currentIndex >= 0
                }
            }

            delegate: Item {
                width: ListView.view.width
                height: 36
                required property int index
                required property var modelData

                property bool isHovered: hoverHandler.hovered
                property bool isSelected: index === root.currentIndex
                property bool isHighlighted: ListView.isCurrentItem

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    text: typeof modelData === "string" ? modelData : (modelData.text || modelData.name || "")
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-1)
                    color: {
                        if (isHighlighted || isHovered) return Colors.overPrimary;
                        return Colors.overBackground;
                    }
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                HoverHandler {
                    id: hoverHandler
                    onHoveredChanged: {
                        if (hovered)
                            listView.currentIndex = index;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.select(index)
                }
            }
        }
    }

    function select(index) {
        if (index < 0 || index >= model.length)
            return;
        popup.close();
        if (index !== root.currentIndex)
            root.activated(index);
    }
}

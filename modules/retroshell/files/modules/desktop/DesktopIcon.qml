import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    focus: root.editMode

    required property string itemName
    required property string itemPath
    required property string itemType
    required property string itemIcon
    property bool isDesktopFile: false

    property bool editMode: false
    property bool isNewItem: false
    property bool selected: false

    signal activated
    signal contextMenuRequested
    signal editCommitted(string newName)
    signal editCancelled
    signal singleClicked

    function startEdit(presetName, newItem) {
        editField.text = presetName || "";
        isNewItem = newItem === true;
        editMode = true;
        editField.forceActiveFocus();
        editField.cursorPosition = (presetName && !newItem && presetName.lastIndexOf(".") > 0)
                ? presetName.lastIndexOf(".") : presetName ? presetName.length : 0;
    }

    function commitEdit() {
        var name = editField.text.trim();
        if (name.length === 0 && !isNewItem) {
            cancelEdit();
            return;
        }
        if (name.length === 0 && isNewItem) {
            cancelEdit();
            return;
        }
        editMode = false;
        editCommitted(name);
    }

    function cancelEdit() {
        editMode = false;
        editCancelled();
    }

    readonly property string thumbnailPath: {
        const ext = itemPath.substring(itemPath.lastIndexOf('.') + 1).toLowerCase();
        const videoExts = ['mp4', 'webm', 'mov', 'avi', 'mkv', 'gif'];
        const imageExts = ['jpg', 'jpeg', 'png', 'webp', 'tif', 'tiff', 'bmp'];

        if (itemType === 'folder' || isDesktopFile) {
            return '';
        }

        if (videoExts.includes(ext) || imageExts.includes(ext)) {
            const fileName = itemPath.substring(itemPath.lastIndexOf('/') + 1);
            return Quickshell.env("HOME") + "/.cache/retro/shell" + "/desktop_thumbnails/" + fileName + ".jpg";
        }

        return '';
    }

    readonly property bool hasThumbnail: thumbnailPath !== '' && Qt.platform.os !== "windows"
    property int thumbnailRefresh: 0

    FileView {
        path: root.thumbnailPath
        watchChanges: root.hasThumbnail

        onFileChanged: {
            root.thumbnailRefresh++;
        }
    }

    width: Config.desktop.iconSize * 1.5
    height: Config.desktop.iconSize + 40

    Rectangle {
        id: background
        anchors.fill: root
        color: Styling.srItem("overprimary")
        radius: Styling.radius(0)
        opacity: root.selected ? 0.3 : (hoverHandler.hovered ? 0.25 : 0.0)
        border.color: root.selected ? Styling.srItem("overprimary") : "transparent"
        border.width: root.selected ? 2 : 0

        Behavior on color {
            enabled: Config.animDuration > 0
            ColorAnimation {
                duration: Config.animDuration / 2
                easing.type: Easing.OutCubic
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        enabled: !root.editMode
        onDoubleTapped: {
            root.activated();
            if (root.itemType === "trash") {
                DesktopService.openTrash();
            } else if (root.isDesktopFile) {
                console.log("Executing desktop file:", root.itemPath);
                DesktopService.executeDesktopFile(root.itemPath);
            } else if (root.itemType === 'folder') {
                console.log("Opening folder:", root.itemPath);
                DesktopService.openFile(root.itemPath);
            } else {
                console.log("Opening file:", root.itemPath);
                DesktopService.openFile(root.itemPath);
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: !root.editMode
        onTapped: {
            root.contextMenuRequested();
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: root
        anchors.margins: 8
        spacing: 4
        layer.enabled: true
        layer.effect: Shadow {}

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Config.desktop.iconSize
            Layout.preferredHeight: Config.desktop.iconSize

            Loader {
                anchors.centerIn: parent
                width: Config.desktop.iconSize
                height: Config.desktop.iconSize
                sourceComponent: Config.tintIcons && !root.hasThumbnail ? tintedIconComponent : normalIconComponent
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: editField.implicitHeight + 4

            Text {
                id: labelText
                anchors.fill: parent
                text: root.itemName
                color: Config.resolveColor(Config.desktop.textColor)
                font.family: Config.defaultFont
                font.pixelSize: Styling.fontSize(0)
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                visible: !root.editMode
            }

            TextInput {
                id: editField
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: Config.resolveColor(Config.desktop.textColor)
                font.family: Config.defaultFont
                font.pixelSize: Styling.fontSize(0)
                font.weight: Font.Bold
                horizontalAlignment: TextInput.AlignHCenter
                visible: root.editMode
                clip: true
                maximumLength: 255
                selectByMouse: true
                activeFocusOnPress: true
                selectionColor: Styling.srItem("overprimary")
                selectedTextColor: Colors.overPrimary
                validator: RegularExpressionValidator { regularExpression: /[^\/]{0,255}/ }

                onEditingFinished: {
                    if (root.editMode) root.commitEdit();
                }

                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Escape) {
                        root.cancelEdit();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.commitEdit();
                        event.accepted = true;
                    }
                }
            }
        }
    }

    Component {
        id: normalIconComponent
        Image {
            mipmap: false
            property bool thumbnailExists: false
            source: {
                root.thumbnailRefresh;
                if (root.hasThumbnail) {
                    return "file://" + root.thumbnailPath;
                }
                return "image://icon/" + root.itemIcon;
            }
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            cache: false

            onStatusChanged: {
                if (status === Image.Ready && root.hasThumbnail) {
                    thumbnailExists = true;
                } else if (status === Image.Error && root.hasThumbnail) {
                    thumbnailExists = false;
                    source = "image://icon/" + root.itemIcon;
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Colors.outline
                border.width: parent.status === Image.Error ? 1 : 0
                radius: 4

                Text {
                    anchors.centerIn: parent
                    text: root.itemType === 'folder' ? "📁" : "📄"
                    visible: parent.parent.status === Image.Error
                    font.pixelSize: Config.desktop.iconSize / 2
                }
            }
        }
    }

    Component {
        id: tintedIconComponent
        Tinted {
            sourceItem: Image {
                mipmap: false
                property bool thumbnailExists: false
                source: {
                    root.thumbnailRefresh;
                    if (root.hasThumbnail) {
                        return "file://" + root.thumbnailPath;
                    }
                    return "image://icon/" + root.itemIcon;
                }
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                cache: false

                onStatusChanged: {
                    if (status === Image.Ready && root.hasThumbnail) {
                        thumbnailExists = true;
                    } else if (status === Image.Error && root.hasThumbnail) {
                        thumbnailExists = false;
                        source = "image://icon/" + root.itemIcon;
                    }
                }
            }
        }
    }
}

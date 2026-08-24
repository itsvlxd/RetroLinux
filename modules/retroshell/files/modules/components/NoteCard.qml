import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.config

// Pinned note card — Apple Notes style: amber folder header with the note
// date, dotted perforation divider, off-white body with editable note content.
Rectangle {
    id: root

    property bool showBackground: true
    property string noteTitle: ""
    property string noteBody: ""
    property string richBody: ""
    property bool hasNotes: false
    property string dateText: ""
    property bool openFullscreen: false
    property real fontSize: 13
    property bool editing: false

    signal saveRequested(string body)
    signal openFullscreenRequested()

    onEditingChanged: {
        if (root.editing)
            Qt.callLater(function () { editor.forceActiveFocus(); });
    }

    readonly property color bodyBg: Colors.surfaceContainer
    readonly property color headerBg: "#FFC107"
    readonly property color charcoal: Colors.overBackground
    readonly property color dividerColor: Colors.outlineVariant
    readonly property int headerHeight: 30

    radius: 24
    clip: true

    // Body surface
    Rectangle {
        anchors.fill: parent
        visible: root.showBackground
        radius: 24
        color: root.bodyBg
    }

    // ── Amber header (title + date) ──
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.headerHeight
        color: root.headerBg

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 8

            Text {
                text: Icons.folder
                font.family: Icons.font
                font.pixelSize: 14
                color: "#FFFFFF"
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                Layout.fillWidth: true
                text: root.hasNotes && root.noteTitle.length > 0 ? root.noteTitle : "Notes"
                color: "#FFFFFF"
                font.family: Config.theme.font
                font.pixelSize: 13
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: root.dateText
                color: Qt.rgba(1, 1, 1, 0.9)
                font.family: Config.theme.font
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    // ── Perforation divider (dotted) ──
    Repeater {
        model: Math.max(0, Math.ceil(root.width / 6))
        delegate: Rectangle {
            width: 2
            height: 1
            color: root.dividerColor
            x: index * 6
            y: root.headerHeight + 1
        }
    }

    // ── Body: formatted review (click to edit) / plain editor ──
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: root.headerHeight + 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.bottomMargin: 10
        radius: 6
        color: "transparent"

        // Formatted markdown/html review (read-only, scrollable)
        Flickable {
            id: viewFlick
            anchors.fill: parent
            anchors.margins: 2
            visible: root.hasNotes && !root.editing
            contentHeight: view.contentHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            TextEdit {
                id: view
                width: viewFlick.width
                height: view.contentHeight
                readOnly: true
                color: root.charcoal
                font.family: Config.theme.font
                font.pixelSize: root.fontSize
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                textFormat: TextEdit.RichText
                text: root.richBody

                TapHandler {
                    onTapped: {
                        if (root.openFullscreen)
                            root.openFullscreenRequested();
                        else
                            root.editing = true;
                    }
                }
            }
        }

        // Plain-text editor (edit mode, scrollable)
        Flickable {
            id: editFlick
            anchors.fill: parent
            anchors.margins: 2
            visible: root.hasNotes && root.editing && !root.openFullscreen
            contentHeight: editor.contentHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            TextEdit {
                id: editor
                width: editFlick.width
                height: editor.contentHeight
                readOnly: false
                color: root.charcoal
                font.family: Config.theme.font
                font.pixelSize: root.fontSize
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                textFormat: TextEdit.PlainText

                property bool _syncing: false

                Connections {
                    target: root
                    function onNoteBodyChanged() {
                        if (!editor._syncing && editor.text !== root.noteBody) {
                            editor._syncing = true;
                            editor.text = root.noteBody;
                            editor._syncing = false;
                        }
                    }
                }

                onTextChanged: {
                    if (!editor._syncing && editor.text !== root.noteBody)
                        saveTimer.restart();
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: editor.forceActiveFocus()
                }

                onActiveFocusChanged: {
                    if (!editor.activeFocus && root.editing)
                        root.editing = false;
                }

                // Keep the caret visible while typing.
                onCursorRectangleChanged: {
                    var f = editFlick;
                    var y = editor.cursorRectangle.y + editor.cursorRectangle.height;
                    if (y > f.contentY + f.height - 4)
                        f.contentY = y - f.height + 4;
                    else if (editor.cursorRectangle.y < f.contentY + 4)
                        f.contentY = editor.cursorRectangle.y - 4;
                }

                Timer {
                    id: saveTimer
                    interval: 600
                    repeat: false
                    onTriggered: {
                        if (editor.text !== root.noteBody)
                            root.saveRequested(editor.text);
                    }
                }
            }
        }
    }

    // Fullscreen preview click (covers the whole card)
    MouseArea {
        anchors.fill: parent
        visible: root.openFullscreen && root.hasNotes
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openFullscreenRequested()
    }
}
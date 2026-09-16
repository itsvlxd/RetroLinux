import QtQuick
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config
import qs.modules.widgets.desktop

// Desktop note widget — 2x2 (160x160) Apple Notes-style pinned note.
// Supports markdown (.md) and rich-text (.html) notes from the shared store.
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    readonly property string noteId: (root.widgetData && root.widgetData.noteId)
        ? String(root.widgetData.noteId) : ""
    readonly property real fontSize: (root.widgetData && root.widgetData.fontSize)
        ? Number(root.widgetData.fontSize) : 13
    readonly property bool openFullscreen: (root.widgetData && root.widgetData.openFullscreen !== undefined)
        ? root.widgetData.openFullscreen === true : false

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            NotesStore { id: store }

            property string currentId: ""
            property string currentTitle: ""
            property string currentContent: ""
            property string currentBody: ""
            property string currentModified: ""
            property bool currentIsMarkdown: false
            property bool currentTitleStripped: false
            property string lastModified: ""
            property real lastUserEdit: 0

            // Light markdown → HTML for the formatted review view.
            function mdToHtml(text) {
                var s = String(text || "");
                s = s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                s = s.replace(/^### (.*)$/gm, "<b>$1</b>");
                s = s.replace(/^## (.*)$/gm, "<b>$1</b>");
                s = s.replace(/^# (.*)$/gm, "<b>$1</b>");
                s = s.replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>");
                s = s.replace(/(^|[^*])\*([^*\n]+)\*/g, "$1<i>$2</i>");
                s = s.replace(/~~([^~\n]+)~~/g, "<s>$1</s>");
                s = s.replace(/`([^`\n]+)`/g, "$1");
                s = s.replace(/\n/g, "<br/>");
                return s;
            }

            readonly property string currentRichBody: content.currentIsMarkdown
                ? content.mdToHtml(content.currentBody)
                : content.currentContent

            function formatDate(iso) {
                if (!iso) return "";
                var d = new Date(iso);
                return (d.getMonth() + 1) + "/" + d.getDate() + "/" + (d.getFullYear() % 100);
            }

            // Body shown/edited in the card: markdown loses a matching leading
            // "# Title" line (the header shows the title), html gets tags stripped.
            function computeBody(raw, title, isMarkdown) {
                var text = String(raw || "");
                if (isMarkdown) {
                    var lines = text.split("\n");
                    if (lines.length && lines[0].trim() === "# " + title) {
                        content.currentTitleStripped = true;
                        lines.shift();
                        return lines.join("\n").replace(/^\n+/, "");
                    }
                    content.currentTitleStripped = false;
                    return text;
                }
                content.currentTitleStripped = false;
                return text.replace(/<[^>]*>/g, "");
            }

            function loadTarget() {
                if (store.notes.length === 0) {
                    content.currentId = "";
                    content.currentTitle = "";
                    content.currentContent = "";
                    content.currentBody = "";
                    content.currentModified = "";
                    content.lastModified = "";
                    return;
                }
                var target = null;
                if (root.noteId) {
                    for (var i = 0; i < store.notes.length; i++)
                        if (store.notes[i].id === root.noteId) { target = store.notes[i]; break; }
                }
                if (!target) target = store.notes[0];

                if (content.currentId !== target.id) {
                    content.currentId = target.id;
                    content.currentTitle = target.title;
                    content.currentIsMarkdown = target.isMarkdown || false;
                    content.currentModified = target.modified || "";
                    content.currentContent = "";
                    content.currentBody = "";
                    content.lastModified = target.modified || "";
                    store.readNote(target.id, target.isMarkdown);
                } else if (content.currentContent === "") {
                    content.lastModified = target.modified || "";
                    store.readNote(target.id, target.isMarkdown);
                }
            }

            // Re-read the current note when its modified timestamp changed
            // (edits made in the launcher / elsewhere), unless the user is
            // actively typing here.
            function checkModified() {
                if (!content.currentId) return;
                var n = store.findNote(content.currentId);
                if (!n) return;
                if (Date.now() - content.lastUserEdit < 3000) return;
                if (n.modified && n.modified !== content.lastModified) {
                    content.currentTitle = n.title;
                    content.currentIsMarkdown = n.isMarkdown || false;
                    content.currentModified = n.modified;
                    content.currentContent = "";
                    content.currentBody = "";
                    content.lastModified = n.modified;
                    store.readNote(n.id, n.isMarkdown);
                }
            }

            Timer {
                interval: 30000
                repeat: true
                running: true
                onTriggered: store.refresh()
            }

            Connections {
                target: store
                function onNotesRefreshed() {
                    content.loadTarget();
                    content.checkModified();
                }
                function onNoteLoaded(noteId, noteContent) {
                    if (noteId === content.currentId) {
                        content.currentContent = noteContent;
                        content.currentBody = content.computeBody(noteContent, content.currentTitle, content.currentIsMarkdown);
                        content.lastModified = content.currentModified;
                    }
                }
                function onNoteCreated(noteId) {
                    content.currentId = noteId;
                    content.loadTarget();
                }
                function onNoteDeleted(noteId) {
                    if (content.currentId === noteId) {
                        content.currentId = "";
                        content.loadTarget();
                    }
                }
                function onNoteSaved(noteId) {
                    if (noteId === content.currentId) {
                        var n = store.findNote(noteId);
                        if (n) content.lastModified = n.modified;
                    }
                }
            }

            Connections {
                target: root
                function onNoteIdChanged() { content.loadTarget(); }
            }

            NoteCard {
                anchors.fill: parent
                noteTitle: content.currentTitle
                noteBody: content.currentBody
                richBody: content.currentRichBody
                hasNotes: store.notes.length > 0
                dateText: content.formatDate(content.currentModified)
                openFullscreen: root.openFullscreen
                fontSize: root.fontSize
                onSaveRequested: function (bodyText) {
                    if (!content.currentId) return;
                    content.lastUserEdit = Date.now();
                    var raw;
                    if (content.currentIsMarkdown) {
                        raw = content.currentTitleStripped
                            ? "# " + content.currentTitle + "\n\n" + bodyText
                            : bodyText;
                    } else {
                        raw = bodyText;
                    }
                    store.saveNote(content.currentId, raw, content.currentIsMarkdown);
                }
                onOpenFullscreenRequested: {
                    // Open the full notes editor (launcher notes tab).
                    GlobalShortcuts.toggleLauncherWithPrefix(4, Config.prefix.notes + " ");
                }
            }

            Component.onCompleted: store.refresh()
        }
    }
}
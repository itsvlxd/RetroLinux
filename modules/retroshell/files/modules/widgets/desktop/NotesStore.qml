import QtQuick
import Quickshell
import Quickshell.Io

// Shared file-based notes store for the desktop notes widgets. Reads/writes the
// same store as the dashboard notes tab (~/.local/share/retroshell-notes).
Item {
    id: store

    readonly property string notesDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/retroshell-notes"
    readonly property string indexPath: notesDir + "/index.json"
    readonly property string notesPath: notesDir + "/notes"

    property var notes: []
    signal notesRefreshed()
    signal noteLoaded(string noteId, string content)
    signal noteCreated(string noteId)
    signal noteDeleted(string noteId)
    signal noteSaved(string noteId)

    function generateUUID() {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
            var r = Math.random() * 16 | 0;
            var v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    }

    function getCurrentTimestamp() {
        return new Date().toISOString();
    }

    function noteExtension(isMarkdown) {
        return isMarkdown ? ".md" : ".html";
    }

    function stripHtml(text) {
        return String(text).replace(/<[^>]*>/g, "");
    }

    function findNote(noteId) {
        for (var i = 0; i < store.notes.length; i++)
            if (store.notes[i].id === noteId)
                return store.notes[i];
        return null;
    }

    // ── Index helpers ──
    function buildIndexData() {
        var order = [];
        var notesMap = {};
        for (var i = 0; i < store.notes.length; i++) {
            var n = store.notes[i];
            order.push(n.id);
            notesMap[n.id] = {
                title: n.title,
                created: n.created,
                modified: n.modified,
                isMarkdown: n.isMarkdown || false
            };
        }
        return { order: order, notes: notesMap };
    }

    function writeIndex() {
        saveIndexProc.command = ["sh", "-c", "printf '%s' '" + JSON.stringify(store.buildIndexData(), null, 2).replace(/'/g, "'\\''") + "' > '" + indexPath + "'"];
        saveIndexProc.running = true;
    }

    function touchModified(noteId) {
        var n = store.findNote(noteId);
        if (n) n.modified = store.getCurrentTimestamp();
    }

    function refresh() {
        initDirProc.running = true;
    }

    function readNote(noteId, isMarkdown) {
        readNoteProc.noteId = noteId;
        readNoteProc.command = ["cat", notesPath + "/" + noteId + noteExtension(isMarkdown)];
        readNoteProc.running = true;
    }

    function saveNote(noteId, content, isMarkdown) {
        saveNoteProc.noteId = noteId;
        saveNoteProc.command = ["sh", "-c", "printf '%s' '" + String(content).replace(/'/g, "'\\''") + "' > '" + notesPath + "/" + noteId + noteExtension(isMarkdown) + "'"];
        saveNoteProc.running = true;
    }

    function createNote(title) {
        var noteId = store.generateUUID();
        var noteTitle = title && title.length > 0 ? title : "Untitled Note";
        var initialContent = "# " + noteTitle + "\n\n";
        createNoteProc.noteId = noteId;
        createNoteProc.noteTitle = noteTitle;
        createNoteProc.command = ["sh", "-c", "mkdir -p '" + notesPath + "' && printf '%s' '" + initialContent.replace(/'/g, "'\\''") + "' > '" + notesPath + "/" + noteId + ".md'"];
        createNoteProc.running = true;
    }

    function deleteNote(noteId, isMarkdown) {
        deleteNoteProc.noteId = noteId;
        deleteNoteProc.command = ["rm", "-f", notesPath + "/" + noteId + noteExtension(isMarkdown)];
        deleteNoteProc.running = true;
    }

    function updateTitle(noteId, newTitle) {
        readIndexForTitle.noteId = noteId;
        readIndexForTitle.newTitle = newTitle;
        readIndexForTitle.command = ["cat", indexPath];
        readIndexForTitle.running = true;
    }

    // Keep the store in sync when the dashboard (or anything else) edits notes.
    FileView {
        path: store.indexPath
        watchChanges: true
        printErrors: false
        onFileChanged: store.refresh()
    }

    // ── Processes ──
    Process {
        id: initDirProc
        command: ["sh", "-c",
            "mkdir -p '" + store.notesPath + "' && [ -f '" + store.indexPath + "' ] || printf '{\"order\":[],\"notes\":{}}' > '" + store.indexPath + "'"]
        running: false
        onExited: function (code) {
            if (code === 0) readIndexProc.running = true;
        }
    }

    Process {
        id: readIndexProc
        command: ["cat", store.indexPath]
        running: false
        property string stdoutData: ""
        stdout: SplitParser { onRead: data => readIndexProc.stdoutData += data + "\n" }
        onExited: function (code) {
            var raw = readIndexProc.stdoutData.trim();
            readIndexProc.stdoutData = "";
            var order = [];
            var map = {};
            try {
                var data = JSON.parse(raw);
                order = data.order || [];
                map = data.notes || {};
            } catch (e) {}
            var list = [];
            for (var i = 0; i < order.length; i++) {
                var meta = map[order[i]];
                if (!meta) continue;
                list.push({
                    id: order[i],
                    title: meta.title || "Untitled",
                    created: meta.created || "",
                    modified: meta.modified || "",
                    isMarkdown: meta.isMarkdown || false
                });
            }
            store.notes = list;
            store.notesRefreshed();
        }
    }

    Process {
        id: readNoteProc
        running: false
        property string noteId: ""
        property string stdoutData: ""
        stdout: SplitParser { onRead: data => readNoteProc.stdoutData += data + "\n" }
        onExited: function (code) {
            var id = readNoteProc.noteId;
            var content = readNoteProc.stdoutData.replace(/\n$/, "");
            readNoteProc.stdoutData = "";
            readNoteProc.noteId = "";
            store.noteLoaded(id, content);
        }
    }

    Process {
        id: saveNoteProc
        running: false
        property string noteId: ""
        onExited: function (code) {
            if (code === 0 && saveNoteProc.noteId) {
                store.touchModified(saveNoteProc.noteId);
                store.writeIndex();
                store.noteSaved(saveNoteProc.noteId);
                saveNoteProc.noteId = "";
            }
        }
    }

    Process {
        id: createNoteProc
        running: false
        property string noteId: ""
        property string noteTitle: ""
        onExited: function (code) {
            if (code === 0 && createNoteProc.noteId) {
                var now = store.getCurrentTimestamp();
                store.notes = [{
                    id: createNoteProc.noteId,
                    title: createNoteProc.noteTitle || "Untitled Note",
                    created: now,
                    modified: now,
                    isMarkdown: true
                }].concat(store.notes);
                store.writeIndex();
                store.noteCreated(createNoteProc.noteId);
            }
            createNoteProc.noteId = "";
            createNoteProc.noteTitle = "";
        }
    }

    Process {
        id: deleteNoteProc
        running: false
        property string noteId: ""
        onExited: function (code) {
            if (code === 0 && deleteNoteProc.noteId) {
                store.notes = store.notes.filter(function (n) { return n.id !== deleteNoteProc.noteId; });
                store.writeIndex();
                store.noteDeleted(deleteNoteProc.noteId);
            }
            deleteNoteProc.noteId = "";
        }
    }

    Process {
        id: readIndexForTitle
        running: false
        property string noteId: ""
        property string newTitle: ""
        property string stdoutData: ""
        stdout: SplitParser { onRead: data => readIndexForTitle.stdoutData += data + "\n" }
        onExited: function (code) {
            var raw = readIndexForTitle.stdoutData.trim();
            readIndexForTitle.stdoutData = "";
            var order = [];
            var map = {};
            try {
                var data = JSON.parse(raw);
                order = data.order || [];
                map = data.notes || {};
            } catch (e) {}
            if (map[readIndexForTitle.noteId]) {
                map[readIndexForTitle.noteId].title = readIndexForTitle.newTitle;
                map[readIndexForTitle.noteId].modified = store.getCurrentTimestamp();
            }
            saveIndexProc.command = ["sh", "-c", "printf '%s' '" + JSON.stringify({ order: order, notes: map }, null, 2).replace(/'/g, "'\\''") + "' > '" + store.indexPath + "'"];
            saveIndexProc.running = true;
            var n = store.findNote(readIndexForTitle.noteId);
            if (n) { n.title = readIndexForTitle.newTitle; n.modified = store.getCurrentTimestamp(); }
            readIndexForTitle.noteId = "";
            readIndexForTitle.newTitle = "";
            store.notesRefreshed();
        }
    }

    Process {
        id: saveIndexProc
        running: false
        onExited: function (code) {}
    }
}
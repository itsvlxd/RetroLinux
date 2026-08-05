pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string desktopDir: ""
    property bool initialLoadComplete: false
    property string positionsFile: Quickshell.dataPath("desktop-positions.json")
    property int maxRowsHint: 15
    property int maxColumnsHint: 10
    property bool gridReady: false
    property bool positionsLoaded: false

    property string copiedPath: ""

    property bool trashHasItems: false

    signal trashChanged()

    onMaxRowsHintChanged: checkGridReady()
    onMaxColumnsHintChanged: checkGridReady()
    onPositionsLoadedChanged: checkGridReady()

    function checkGridReady() {
        if (maxRowsHint > 0 && maxColumnsHint > 0 && positionsLoaded && !gridReady) {
            gridReady = true;
            console.log("Grid ready - rows:", maxRowsHint, "cols:", maxColumnsHint);
            if (tempItems.length > 0 || tempDesktopFiles.length > 0) {
                console.log("Finalizing items with", tempItems.length + tempDesktopFiles.length, "items");
                finalizeItems();
            }
        }
    }

    property ListModel items: ListModel {
        id: itemsModel
    }

    property var iconPositions: ({})

    function savePositions() {
        var json = JSON.stringify(iconPositions, null, 2);
        savePositionsProcess.command = ["sh", "-c", "echo '" + json.replace(/'/g, "'\\''") + "' > " + positionsFile];
        savePositionsProcess.running = true;
    }

    function loadPositions() {
        loadPositionsProcess.running = true;
    }

    function updateIconPosition(path, gridX, gridY) {
        iconPositions[path] = {
            x: gridX,
            y: gridY
        };
        savePositions();
    }

    function getIconPosition(path) {
        return iconPositions[path] || null;
    }

    function calculateAutoPosition(index) {
        var usedPositions = {};

        for (var key in iconPositions) {
            var pos = iconPositions[key];
            usedPositions[pos.x + "," + pos.y] = true;
        }

        var gridX = 0;
        var gridY = 0;
        var checked = 0;

        while (checked <= index) {
            var posKey = gridX + "," + gridY;
            if (!usedPositions[posKey]) {
                if (checked === index) {
                    return {
                        x: gridX,
                        y: gridY
                    };
                }
                checked++;
            }
            gridY++;
            if (gridY >= maxRowsHint) {
                gridY = 0;
                gridX++;
            }
        }

        return {
            x: gridX,
            y: gridY
        };
    }

    function getDesktopDir() {
        getDesktopDirProcess.running = true;
    }

    function generateThumbnails() {
        if (desktopDir) {
            thumbnailProcess.running = true;
        }
    }

    function scanDesktop() {
        if (desktopDir) {
            if (parsingInProgress) {
                needsRescan = true;
            } else {
                scanProcess.running = true;
            }
        }
    }

    function parseDesktopFile(filePath) {
        parseDesktopProcess.command = ["cat", filePath];
        parseDesktopProcess.running = true;
    }

    function refreshTrash() {
        trashCountProcess.running = true;
    }

    function emptyTrash() {
        var emp = Qt.createQmlObject('
            import Quickshell
            import Quickshell.Io
            Process {
                running: true
                command: ["gio", "trash", "--empty"]
                onExited: {
                    root.refreshTrash();
                    destroy();
                }
            }
        ', root);
    }

    function openTrash() {
        runInActiveWorkspace("nemo trash:///");
    }

    function bulkTrash(indices) {
        if (!indices || indices.length === 0) return;
        for (var i = 0; i < indices.length; i++) {
            var idx = indices[i];
            if (idx < 0 || idx >= items.count) continue;
            var it = items.get(idx);
            if (!it || it.isPlaceholder || !it.path || it.path === "__placeholder__" || it.path === "trash:///virtual") continue;
            trashFile(it.path);
        }
        refreshTrash();
        scanDesktop();
    }

    function bulkOpen(indices) {
        if (!indices || indices.length === 0) return;
        for (var i = 0; i < indices.length; i++) {
            var idx = indices[i];
            if (idx < 0 || idx >= items.count) continue;
            var it = items.get(idx);
            if (!it || it.isPlaceholder || !it.path || it.path === "__placeholder__" || it.path === "trash:///virtual") continue;
            if (it.isDesktopFile) executeDesktopFile(it.path);
            else openFile(it.path);
        }
    }

    function bulkMove(indices, targetIndex) {
        if (!indices || indices.length <= 1) return;
        var sorted = indices.slice().sort((a, b) => a - b);
        var draggedIdx = sorted.indexOf(indices[0]) >= 0 ? indices[0] : sorted[0];
        // Calculate the delta: how far the dragged item moved
        var delta = targetIndex - draggedIdx;
        console.log("bulkMove: sorted=", JSON.stringify(sorted), "target=", targetIndex, "dragged=", draggedIdx, "delta=", delta);

        // Save current positions for ALL items first
        saveAllPositions();

        // Remove selected items from their current positions (set as placeholders)
        var selectedPaths = [];
        for (var i = 0; i < sorted.length; i++) {
            var idx = sorted[i];
            if (idx < 0 || idx >= items.count) continue;
            var it = items.get(idx);
            if (!it || it.isPlaceholder || !it.path || it.path === "__placeholder__" || it.path === "trash:///virtual") continue;
            selectedPaths.push(it.path);
            items.setProperty(idx, "name", "");
            items.setProperty(idx, "path", "");
            items.setProperty(idx, "type", "placeholder");
            items.setProperty(idx, "icon", "text-x-generic");
            items.setProperty(idx, "isDesktopFile", false);
            items.setProperty(idx, "isPlaceholder", true);
        }

        // Now compute where each selected item should go.
        // Items shift when we modify the model, so we use the original
        // grid positions with the delta applied, bounded to the grid.
        var maxIdx = maxRowsHint * maxColumnsHint;
        for (var j = 0; j < selectedPaths.length; j++) {
            var origIdx = sorted[j];
            var newIdx = Math.max(0, Math.min(maxIdx - 1, origIdx + delta));
            // If new position is already occupied by another selection, shift it
            while (newIdx >= 0 && newIdx < items.count) {
                // Check if this spot is free (placeholder or just-cleared)
                var cell = items.get(newIdx);
                if (cell && (cell.isPlaceholder || cell.path === "" || cell.path === "__placeholder__")) break;
                // Check if this path is one of our selected ones
                if (selectedPaths.indexOf(cell.path) >= 0) break;
                newIdx++;
            }
            if (newIdx >= maxIdx) newIdx = maxIdx - 1;
            if (newIdx < 0) newIdx = 0;

            var col = Math.floor(newIdx / maxRowsHint);
            var row = newIdx % maxRowsHint;
            console.log("bulkMove: placing", selectedPaths[j], "at idx", newIdx, "col", col, "row", row);
            updateIconPosition(selectedPaths[j], col, row);
        }

        // Rescan to rebuild grid with new positions
        scanDesktop();
    }

    Process {
        id: trashCountProcess
        running: false
        command: ["sh", "-c", "gio trash --list 2>/dev/null | wc -l"]

        stdout: StdioCollector {
            onStreamFinished: {
                var count = parseInt(text.trim()) || 0;
                var hadItems = root.trashHasItems;
                root.trashHasItems = count > 0;
                // Update trash icon in the items model
                for (var ti = 0; ti < items.count; ti++) {
                    var it = items.get(ti);
                    if (it.type === "trash") {
                        items.setProperty(ti, "icon", root.trashHasItems ? "user-trash-full" : "user-trash");
                        break;
                    }
                }
                if (root.trashHasItems !== hadItems) {
                    root.trashChanged();
                }
            }
        }
    }

    function executeDesktopFile(filePath) {
        var escapedPath = filePath.replace(/'/g, "'\\''");
        runInActiveWorkspace("gio launch '" + escapedPath + "'");
    }

    function openFile(filePath) {
        var escapedPath = filePath.replace(/'/g, "'\\''");
        runInActiveWorkspace("xdg-open '" + escapedPath + "'");
    }

    function runInActiveWorkspace(command) {
        var processComponent = Qt.createQmlObject('import Quickshell.Io; Process { }', root);
        processComponent.command = ["bash", "-c", "cd ~ && env -u HL_INITIAL_WORKSPACE_TOKEN setsid " + command + " < /dev/null > /dev/null 2>&1 &"];
        processComponent.onExited.connect(() => processComponent.destroy());
        processComponent.running = true;
    }

    function trashFile(filePath) {
        var escapedPath = filePath.replace(/'/g, "'\\''");
        var processComponent = Qt.createQmlObject('
            import Quickshell
            import Quickshell.Io
            Process {
                running: true
                command: ["bash", "-c", "gio trash \'' + escapedPath + '\'"]

                stdout: StdioCollector {
                    onStreamFinished: {
                        if (text.length > 0) {
                            console.log("File moved to trash:", text);
                        }
                    }
                }

                stderr: StdioCollector {
                    onStreamFinished: {
                        if (text.length > 0) {
                            console.warn("Error moving file to trash:", text);
                        }
                    }
                }

                onRunningChanged: {
                    if (!running) {
                        root.refreshTrash();
                        destroy();
                    }
                }
            }
        ', root);
    }

    function renameFile(filePath, newName) {
        var dir = filePath.substring(0, filePath.lastIndexOf("/"));
        var escapedDir = dir.replace(/'/g, "'\\''");
        var escapedPath = filePath.replace(/'/g, "'\\''");
        launchProcess.command = ["bash", "-c", "mv '" + escapedPath + "' '" + escapedDir + "/'$(printf '%q' '" + newName.replace(/'/g, "'\\''") + "')"];
        launchProcess.running = true;
    }

    function createNew(type, dir, name) {
        var escapedDir = dir.replace(/'/g, "'\\''");
        var escapedName = name.replace(/'/g, "'\\''");
        var cmd = type === "folder"
                ? "mkdir -p '" + escapedDir + "/'$(printf '%q' \"" + escapedName + "\")"
                : "touch '" + escapedDir + "/'$(printf '%q' \"" + escapedName + "\")";
        var proc = Qt.createQmlObject('
            import Quickshell
            import Quickshell.Io
            Process {
                running: true
                command: ["bash", "-c", ' + JSON.stringify(cmd) + ']
                onExited: { root.scanDesktop(); destroy(); }
            }
        ', root);
    }

    function addPlaceholder(type, icon, col, row) {
        // Adds a visible placeholder item at the given grid position.
        // Caller removes it after create/rename commits.
        var idx = col * maxRowsHint + row;
        if (idx < 0 || idx >= items.count) return idx;
        items.setProperty(idx, "name", type === "folder" ? "New Folder" : "New File");
        items.setProperty(idx, "path", "__placeholder__");
        items.setProperty(idx, "type", "placeholder-new");
        items.setProperty(idx, "icon", icon || (type === "folder" ? "folder" : "document-new"));
        items.setProperty(idx, "isDesktopFile", false);
        items.setProperty(idx, "isPlaceholder", false);
        items.setProperty(idx, "gridX", col);
        items.setProperty(idx, "gridY", row);
        return idx;
    }

    function clearPlaceholder(idx) {
        if (idx < 0 || idx >= items.count) return;
        items.setProperty(idx, "name", "");
        items.setProperty(idx, "path", "");
        items.setProperty(idx, "type", "placeholder");
        items.setProperty(idx, "icon", "text-x-generic");
        items.setProperty(idx, "isDesktopFile", false);
        items.setProperty(idx, "isPlaceholder", true);
        items.setProperty(idx, "gridX", Math.floor(idx / maxRowsHint));
        items.setProperty(idx, "gridY", idx % maxRowsHint);
    }

    function copyFilePath(filePath) {
        root.copiedPath = filePath;
        console.log("Copied path:", filePath);
    }

    function pasteFile(targetDir, col, row) {
        if (!root.copiedPath) return;
        var escapedSrc = root.copiedPath.replace(/'/g, "'\\''");
        var escapedDst = targetDir.replace(/'/g, "'\\''");
        var colVal = (col !== undefined && col >= 0) ? col : -1;
        var rowVal = (row !== undefined && row >= 0) ? row : -1;
        var cmd = "src='" + escapedSrc + "'; name=$(basename \"$src\"); base=\"${name%.*}\"; ext=\"${name##*.}\"; "
                + "dst='" + escapedDst + "/'\"$name\"; finalname=\"$name\"; "
                + "if [ ! -e \"$dst\" ]; then cp -r \"$src\" \"$dst\"; else "
                + "action=$(zenity --list --radiolist --title='File Conflict' "
                + "  --text=\"$dst already exists. -- What would you like to do?\" "
                + "  --column='' --column='Action' TRUE 'Keep both' FALSE 'Replace' FALSE 'Skip' "
                + "  2>/dev/null); "
                + "if [ \"$action\" = 'Replace' ]; then rm -rf \"$dst\"; cp -r \"$src\" \"$dst\"; "
                + "elif [ \"$action\" = 'Keep both' ]; then "
                + "  n=1; "
                + "  if [ \"$ext\" != \"$base\" ]; then "
                + "    while [ -e '" + escapedDst + "/'\"${base} (${n}).${ext}\" ]; do n=$((n+1)); done; "
                + "    finalname=\"${base} (${n}).${ext}\"; "
                + "    cp -r \"$src\" '" + escapedDst + "/'\"$finalname\"; "
                + "  else "
                + "    while [ -e '" + escapedDst + "/'\"${base} (${n})\" ]; do n=$((n+1)); done; "
                + "    finalname=\"${base} (${n})\"; "
                + "    cp -r \"$src\" '" + escapedDst + "/'\"$finalname\"; "
                + "  fi; "
                + "fi; fi; "
                + "echo \"COPIED:|$finalname|" + colVal + "|" + rowVal + "\"";
        copyPasteProcess.command = ["bash", "-c", cmd];
        copyPasteProcess.running = true;
        root.copiedPath = "";
    }

    Process {
        id: copyPasteProcess
        running: false
        command: []

        stdout: StdioCollector {
            onStreamFinished: {
                var output = text.trim();
                if (output.startsWith("COPIED:")) {
                    var parts = output.split("|");
                    var name = parts[1] || "";
                    var col = parseInt(parts[2]) || -1;
                    var row = parseInt(parts[3]) || -1;
                    var destPath = root.desktopDir + "/" + name;
                    if (col >= 0 && row >= 0 && name) {
                        root.updateIconPosition(destPath, col, row);
                    }
                }
                root.scanDesktop();
                root.refreshTrash();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) console.warn("Copy-paste error:", text);
            }
        }
    }

    function showProperties(filePath) {
        var escapedPath = filePath.replace(/'/g, "'\\''");
        var cmd = "file_path='" + escapedPath + "'; name=$(basename \"$file_path\"); type=$(file -b \"$file_path\" 2>/dev/null || echo 'Unknown'); size=$(du -sh \"$file_path\" 2>/dev/null | cut -f1 || echo 'Unknown'); modified=$(stat -c '%y' \"$file_path\" 2>/dev/null | cut -d. -f1 || echo 'Unknown'); "
                + "dir=$(dirname \"$file_path\"); info=\"Name: $name\nType: $type\nSize: $size\nModified: $modified\nPath: $dir\"; "
                + "zenity --info --title='File Properties' --text=\"$info\" --width=400 2>/dev/null";
        launchProcess.command = ["bash", "-c", cmd];
        launchProcess.running = true;
    }

    function moveToFolder(sourcePath, folderPath) {
        var escapedSrc = sourcePath.replace(/'/g, "'\\''");
        var escapedDst = folderPath.replace(/'/g, "'\\''");
        var cmd = "src='" + escapedSrc + "'; name=$(basename \"$src\"); "
                + "base=\"${name%.*}\"; ext=\"${name##*.}\"; "
                + "dst='" + escapedDst + "/'\"$name\"; "
                + "if [ ! -e \"$dst\" ]; then "
                + "  mv \"$src\" \"$dst\"; "
                + "else "
                + "  action=$(zenity --list --radiolist --title='File Conflict' "
                + "    --text=\"$dst already exists. -- What would you like to do?\" "
                + "    --column='' --column='Action' TRUE 'Keep both' FALSE 'Replace' FALSE 'Cancel' "
                + "    2>/dev/null); "
                + "  if [ \"$action\" = 'Replace' ]; then rm -rf \"$dst\"; mv \"$src\" \"$dst\"; "
                + "  elif [ \"$action\" = 'Keep both' ]; then "
                + "    n=1; "
                + "    if [ \"$ext\" != \"$base\" ]; then "
                + "      while [ -e '" + escapedDst + "/'\"${base} (${n}).${ext}\" ]; do n=$((n+1)); done; "
                + "      mv \"$src\" '" + escapedDst + "/'\"${base} (${n}).${ext}\"; "
                + "    else "
                + "      while [ -e '" + escapedDst + "/'\"${base} (${n})\" ]; do n=$((n+1)); done; "
                + "      mv \"$src\" '" + escapedDst + "/'\"${base} (${n})\"; "
                + "    fi; "
                + "  fi; "
                + "fi";
        launchProcess.command = ["bash", "-c", cmd];
        launchProcess.running = true;
    }

    function importFiles(urls, destDir) {
        if (!urls || !destDir) return;
        for (var i = 0; i < urls.length; i++) {
            var filePath = decodeURIComponent(String(urls[i]).replace(/^file:\/\//, ""));
            var escapedSrc = filePath.replace(/'/g, "'\\''");
            var escapedDst = destDir.replace(/'/g, "'\\''");
            var cmd = "src='" + escapedSrc + "'; name=$(basename \"$src\"); "
                    + "base=\"${name%.*}\"; ext=\"${name##*.}\"; "
                    + "dst='" + escapedDst + "/'\"$name\"; "
                    + "if [ ! -e \"$dst\" ]; then "
                    + "  cp -r \"$src\" \"$dst\"; "
                    + "else "
                    + "  action=$(zenity --list --radiolist --title='File Conflict' "
                    + "    --text=\"$dst already exists. -- What would you like to do?\" "
                    + "    --column='' --column='Action' TRUE 'Keep both' FALSE 'Replace' FALSE 'Skip' "
                    + "    2>/dev/null); "
                    + "  if [ \"$action\" = 'Replace' ]; then rm -rf \"$dst\"; cp -r \"$src\" \"$dst\"; "
                    + "  elif [ \"$action\" = 'Keep both' ]; then "
                    + "    n=1; "
                    + "    if [ \"$ext\" != \"$base\" ]; then "
                    + "      while [ -e '" + escapedDst + "/'\"${base} (${n}).${ext}\" ]; do n=$((n+1)); done; "
                    + "      cp -r \"$src\" '" + escapedDst + "/'\"${base} (${n}).${ext}\"; "
                    + "    else "
                    + "      while [ -e '" + escapedDst + "/'\"${base} (${n})\" ]; do n=$((n+1)); done; "
                    + "      cp -r \"$src\" '" + escapedDst + "/'\"${base} (${n})\"; "
                    + "    fi; "
                    + "  fi; "
                    + "fi";
            var proc = Qt.createQmlObject('
                import Quickshell
                import Quickshell.Io
                Process {
                    running: true
                    command: ["bash", "-c", ' + JSON.stringify(cmd) + ']
                    onExited: { root.scanDesktop(); destroy(); }
                }
            ', root);
        }
    }

    Process {
        id: launchProcess
        running: false
        command: []

        onExited: {
            root.scanDesktop();
            root.refreshTrash();
        }
    }

    function saveAllPositions() {
        iconPositions = {};

        for (var i = 0; i < items.count; i++) {
            var item = items.get(i);
            if (!item.isPlaceholder && item.path) {
                var col = Math.floor(i / maxRowsHint);
                var row = i % maxRowsHint;
                iconPositions[item.path] = {
                    x: col,
                    y: row
                };
            }
        }

        savePositions();
    }

    function moveItem(fromIndex, toIndex) {
        if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 || fromIndex >= items.count) {
            return;
        }

        if (toIndex >= items.count) {
            toIndex = items.count - 1;
        }

        var targetIsPlaceholder = items.get(toIndex).isPlaceholder === true;

        if (targetIsPlaceholder) {
            var item = items.get(fromIndex);
            items.setProperty(toIndex, "name", item.name);
            items.setProperty(toIndex, "path", item.path);
            items.setProperty(toIndex, "type", item.type);
            items.setProperty(toIndex, "icon", item.icon);
            items.setProperty(toIndex, "isDesktopFile", item.isDesktopFile);
            items.setProperty(toIndex, "isPlaceholder", false);

            items.setProperty(fromIndex, "name", "");
            items.setProperty(fromIndex, "path", "");
            items.setProperty(fromIndex, "type", "placeholder");
            items.setProperty(fromIndex, "icon", "");
            items.setProperty(fromIndex, "isDesktopFile", false);
            items.setProperty(fromIndex, "isPlaceholder", true);

            var col = Math.floor(toIndex / maxRowsHint);
            var row = toIndex % maxRowsHint;
            items.setProperty(toIndex, "gridX", col);
            items.setProperty(toIndex, "gridY", row);
        } else {
            items.move(fromIndex, toIndex, 1);

            var sourceCol = Math.floor(toIndex / maxRowsHint);
            var sourceRow = toIndex % maxRowsHint;
            items.setProperty(toIndex, "gridX", sourceCol);
            items.setProperty(toIndex, "gridY", sourceRow);

            var targetCol = Math.floor(fromIndex / maxRowsHint);
            var targetRow = fromIndex % maxRowsHint;
            items.setProperty(fromIndex, "gridX", targetCol);
            items.setProperty(fromIndex, "gridY", targetRow);
        }

        saveAllPositions();
    }

    function getFileType(fileName) {
        var ext = fileName.toLowerCase().split('.').pop();

        if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp'].includes(ext)) {
            return 'image';
        } else if (['mp4', 'webm', 'mov', 'avi', 'mkv', 'mp3', 'wav', 'ogg', 'flac'].includes(ext)) {
            return 'media';
        } else if (['pdf'].includes(ext)) {
            return 'pdf';
        } else if (['txt', 'md', 'log'].includes(ext)) {
            return 'text';
        } else if (['zip', 'tar', 'gz', 'rar', '7z'].includes(ext)) {
            return 'archive';
        } else if (['doc', 'docx', 'odt'].includes(ext)) {
            return 'document';
        }
        return 'file';
    }

    function getIconForType(type) {
        switch (type) {
        case 'folder':
            return 'folder';
        case 'image':
            return 'image-x-generic';
        case 'media':
            return 'video-x-generic';
        case 'pdf':
            return 'application-pdf';
        case 'text':
            return 'text-x-generic';
        case 'archive':
            return 'package-x-generic';
        case 'document':
            return 'x-office-document';
        default:
            return 'text-x-generic';
        }
    }

    property bool _initialized: false

    function initialize() {
        if (_initialized) return;
        _initialized = true;
        Qt.callLater(() => getDesktopDir());
    }

    Process {
        id: savePositionsProcess
        running: false
        command: []

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Error saving positions:", text);
                }
            }
        }
    }

    Process {
        id: loadPositionsProcess
        running: false
        command: ["cat", positionsFile]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    try {
                        var parsed = JSON.parse(text);

                        for (var key in root.iconPositions) {
                            delete root.iconPositions[key];
                        }

                        for (var k in parsed) {
                            root.iconPositions[k] = {
                                x: parsed[k].x,
                                y: parsed[k].y
                            };
                        }

                        console.log("Loaded", Object.keys(root.iconPositions).length, "icon positions");
                    } catch (e) {
                        console.warn("Error parsing positions file:", e);
                    }
                }
                root.positionsLoaded = true;
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                root.positionsLoaded = true;
            }
        }
    }

    Process {
        id: getDesktopDirProcess
        running: false
        command: ["sh", "-c", "echo ${XDG_DESKTOP_DIR:-$HOME/Desktop}"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.desktopDir = text.trim();
                console.log("Desktop directory:", root.desktopDir);
                console.log("Positions file:", root.positionsFile);
                loadPositions();
                scanDesktop();
                directoryWatcher.path = root.desktopDir;
                directoryWatcher.reload();
            }
        }
    }

    FileView {
        id: directoryWatcher
        path: ""
        watchChanges: true
        printErrors: false

        onFileChanged: {
            console.log("Desktop directory changed, rescanning...");
            scanDesktop();
            thumbnailTimer.restart();
        }
    }

    Process {
        id: scanProcess
        running: false
        command: ["sh", "-c", "ls -1ap " + root.desktopDir + " | grep -v '^\\.$' | grep -v '^\\.\\.$'"]

        stdout: StdioCollector {
            onStreamFinished: {
                var entries = text.trim().split("\n").filter(f => f.length > 0);
                var newItems = [];
                var pendingDesktopFiles = [];

                for (var i = 0; i < entries.length; i++) {
                    var entry = entries[i];
                    var isDir = entry.endsWith('/');
                    var name = isDir ? entry.slice(0, -1) : entry;
                    var fullPath = root.desktopDir + "/" + name;

                    if (name.startsWith('.')) {
                        continue;
                    }

                    if (isDir) {
                        newItems.push({
                            name: name,
                            path: fullPath,
                            type: 'folder',
                            icon: 'folder',
                            isDesktopFile: false,
                            sortOrder: 0
                        });
                    } else if (name.endsWith('.desktop')) {
                        pendingDesktopFiles.push({
                            name: name,
                            path: fullPath,
                            type: 'application',
                            icon: 'application-x-executable',
                            isDesktopFile: true,
                            sortOrder: 1
                        });
                    } else {
                        var fileType = root.getFileType(name);
                        newItems.push({
                            name: name,
                            path: fullPath,
                            type: fileType,
                            icon: root.getIconForType(fileType),
                            isDesktopFile: false,
                            sortOrder: 2
                        });
                    }
                }

                if (!parsingInProgress) {
                    tempDesktopFiles = pendingDesktopFiles;
                    tempItems = newItems;

                    if (pendingDesktopFiles.length > 0) {
                        parsingInProgress = true;
                        currentDesktopFileIndex = 0;
                        parseNextDesktopFile();
                    } else {
                        if (gridReady && positionsLoaded) {
                            finalizeItems();
                        }
                    }
                } else {
                    needsRescan = true;
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Error scanning desktop:", text);
                }
            }
        }
    }

    property var tempDesktopFiles: []
    property var tempItems: []
    property int currentDesktopFileIndex: -1
    property bool parsingInProgress: false
    property bool needsRescan: false

    function parseNextDesktopFile() {
        if (currentDesktopFileIndex < tempDesktopFiles.length) {
            var item = tempDesktopFiles[currentDesktopFileIndex];
            parseDesktopFileProcess.command = ["cat", item.path];
            parseDesktopFileProcess.running = true;
        } else {
            parsingInProgress = false;
            if (gridReady && positionsLoaded) {
                finalizeItems();
            }
            if (needsRescan) {
                needsRescan = false;
                scanDesktop();
            }
        }
    }

    function finalizeItems() {
        var allItems = tempItems.concat(tempDesktopFiles);

        allItems.sort((a, b) => {
            if (a.sortOrder !== b.sortOrder) {
                return a.sortOrder - b.sortOrder;
            }
            return a.name.localeCompare(b.name);
        });

        items.clear();

        var gridSize = maxRowsHint * maxColumnsHint;

        for (var i = 0; i < gridSize; i++) {
            items.append({
                name: "",
                path: "",
                type: "placeholder",
                icon: "",
                isDesktopFile: false,
                isPlaceholder: true,
                gridX: Math.floor(i / maxRowsHint),
                gridY: i % maxRowsHint
            });
        }

        var usedIndices = {};

        for (var i = 0; i < allItems.length; i++) {
            var item = allItems[i];
            var savedPos = getIconPosition(item.path);
            var gridIndex = -1;

            if (savedPos && savedPos.x < maxColumnsHint && savedPos.y < maxRowsHint) {
                gridIndex = savedPos.x * maxRowsHint + savedPos.y;

                if (usedIndices[gridIndex]) {
                    gridIndex = -1;
                }
            }

            if (gridIndex === -1) {
                for (var j = 0; j < gridSize; j++) {
                    if (!usedIndices[j]) {
                        gridIndex = j;
                        break;
                    }
                }
            }

            if (gridIndex !== -1 && gridIndex < items.count) {
                usedIndices[gridIndex] = true;
                var col = Math.floor(gridIndex / maxRowsHint);
                var row = gridIndex % maxRowsHint;

                items.setProperty(gridIndex, "name", item.name);
                items.setProperty(gridIndex, "path", item.path);
                items.setProperty(gridIndex, "type", item.type);
                items.setProperty(gridIndex, "icon", item.icon);
                items.setProperty(gridIndex, "isDesktopFile", item.isDesktopFile);
                items.setProperty(gridIndex, "isPlaceholder", false);
                items.setProperty(gridIndex, "gridX", col);
                items.setProperty(gridIndex, "gridY", row);
            }
        }

        // Inject persistent Trash item at saved position or last free cell
        var trashPath = "trash:///virtual";
        var trashPos = root.getIconPosition(trashPath);
        var trashIdx = -1;
        if (trashPos && trashPos.x < maxColumnsHint && trashPos.y < maxRowsHint) {
            var ti = trashPos.x * maxRowsHint + trashPos.y;
            if (ti >= 0 && ti < items.count && !usedIndices[ti]) {
                trashIdx = ti;
            }
        }
        if (trashIdx === -1) {
            for (var k = gridSize - 1; k >= 0; k--) {
                if (!usedIndices[k]) {
                    trashIdx = k;
                    break;
                }
            }
        }
        if (trashIdx !== -1 && trashIdx < items.count) {
            usedIndices[trashIdx] = true;
            var tcol = Math.floor(trashIdx / maxRowsHint);
            var trow = trashIdx % maxRowsHint;
            var showFull = root.trashHasItems;
            items.setProperty(trashIdx, "name", "Trash");
            items.setProperty(trashIdx, "path", trashPath);
            items.setProperty(trashIdx, "type", "trash");
            items.setProperty(trashIdx, "icon", showFull ? "user-trash-full" : "user-trash");
            items.setProperty(trashIdx, "isDesktopFile", false);
            items.setProperty(trashIdx, "isPlaceholder", false);
            items.setProperty(trashIdx, "gridX", tcol);
            items.setProperty(trashIdx, "gridY", trow);
            root.updateIconPosition(trashPath, tcol, trow);
        }

        root.initialLoadComplete = true;
        root.refreshTrash();
    }

    Process {
        id: parseDesktopFileProcess
        running: false
        command: []

        onRunningChanged: {
            if (!running && currentDesktopFileIndex >= 0 && currentDesktopFileIndex < tempDesktopFiles.length) {
                currentDesktopFileIndex++;
                if (currentDesktopFileIndex < tempDesktopFiles.length) {
                    Qt.callLater(parseNextDesktopFile);
                } else {
                    parsingInProgress = false;
                    currentDesktopFileIndex = -1;
                    if (gridReady && positionsLoaded) {
                        finalizeItems();
                    }
                    if (needsRescan) {
                        needsRescan = false;
                        scanDesktop();
                    }
                }
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (currentDesktopFileIndex >= tempDesktopFiles.length) {
                    return;
                }

                var item = tempDesktopFiles[currentDesktopFileIndex];
                var lines = text.split("\n");
                var name = "";
                var icon = "application-x-executable";

                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (line.startsWith("Name=")) {
                        name = line.substring(5);
                    } else if (line.startsWith("Icon=")) {
                        icon = line.substring(5);
                    }
                }

                if (name) {
                    item.name = name;
                }
                item.icon = icon;
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Error parsing .desktop file:", text);
                }
                if (currentDesktopFileIndex >= tempDesktopFiles.length) {
                    parsingInProgress = false;
                    if (needsRescan) {
                        needsRescan = false;
                        scanDesktop();
                    }
                    return;
                }
                currentDesktopFileIndex++;
                parseNextDesktopFile();
            }
        }
    }

    Process {
        id: thumbnailProcess
        running: false
        // QUICKSHELL-GIT: command: ["python3", decodeURIComponent(Qt.resolvedUrl("../../scripts/desktop_thumbgen.py").toString().replace("file://", "")), desktopDir, Quickshell.cacheDir + "/desktop_thumbnails"]
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("../../scripts/desktop_thumbgen.py").toString().replace("file://", "")), desktopDir, Quickshell.env("HOME") + "/.cache/retro/shell" + "/desktop_thumbnails"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("Thumbnail generation:", text);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("Thumbnail generation output:", text);
                }
            }
        }
    }

    Timer {
        id: thumbnailTimer
        interval: 1000
        running: false
        onTriggered: generateThumbnails()
    }

    onDesktopDirChanged: {
        if (desktopDir) {
            thumbnailTimer.running = true;
        }
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.desktop
import qs.modules.widgets.desktop
import qs.modules.services
import qs.modules.theme
import qs.config

PanelWindow {
    id: desktop

    property int barSize: Config.showBackground ? 44 : 40
    property int bottomTextMargin: 32
    property string barPosition: ["top", "bottom", "left", "right"].includes(Config.bar.position) ? Config.bar.position : "top"

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    color: "transparent"

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "retroshell:desktop"
    WlrLayershell.keyboardFocus: iconContainer._editActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    visible: Config.desktopLayerActive

    Component.onCompleted: {
        DesktopService.initialize();
        DesktopService.maxRowsHint = Qt.binding(() => iconContainer.maxRows);
        DesktopService.maxColumnsHint = Qt.binding(() => iconContainer.maxColumns);
    }

    Item {
        id: iconContainer
        anchors.fill: parent
        visible: Config.desktop.showIcons
        anchors.margins: 16
        anchors.bottomMargin: desktop.barPosition === "bottom" ? desktop.barSize + 16 : 16
        anchors.topMargin: desktop.barPosition === "top" ? desktop.barSize + 16 : 16
        anchors.leftMargin: desktop.barPosition === "left" ? desktop.barSize + 16 : 16
        anchors.rightMargin: desktop.barPosition === "right" ? desktop.barSize + 16 : 16

        property int cellHeight: Config.desktop.iconSize + 40 + Config.desktop.spacingVertical
        property int cellWidth: cellHeight
        property int maxRows: Math.floor(height / cellHeight)
        property int maxColumns: Math.floor(width / cellWidth)

        property bool _iconMenuOpen: false
        property int _pasteCol: -1
        property int _pasteRow: -1
        property int _pendingEditIdx: -1
        property string _pendingEditType: ""
        property bool _editActive: false
        property var selectedIndices: []
        property int _lastClickedIdx: -1

        function toggleSelection(idx, additive) {
            var arr = selectedIndices.slice();
            var pos = arr.indexOf(idx);
            if (additive) {
                if (pos >= 0) arr.splice(pos, 1); else arr.push(idx);
            } else if (pos >= 0 && arr.length === 1) {
                arr = [];
            } else {
                arr = [idx];
            }
            selectedIndices = arr;
            _lastClickedIdx = idx;
        }

        function rangeSelect(idx) {
            var arr = [];
            var lo = Math.min(_lastClickedIdx >= 0 ? _lastClickedIdx : idx, idx);
            var hi = Math.max(_lastClickedIdx >= 0 ? _lastClickedIdx : idx, idx);
            for (var i = lo; i <= hi; i++) {
                var item = DesktopService.items.get(i);
                if (item && !item.isPlaceholder && item.type !== "trash") arr.push(i);
            }
            selectedIndices = arr;
            _lastClickedIdx = idx;
        }

        function clearSelection() { selectedIndices = []; }

        function selectAll() {
            var arr = [];
            for (var i = 0; i < DesktopService.items.count; i++) {
                var item = DesktopService.items.get(i);
                if (item && !item.isPlaceholder && item.type !== "trash") arr.push(i);
            }
            selectedIndices = arr;
        }

        // External drag-and-drop from file managers
        DropArea {
            id: externalDrop
            anchors.fill: parent
            z: 1
            onDropped: drop => {
                if (!drop.hasUrls) return;
                var pos = Qt.point(drop.x, drop.y);
                var col = Math.floor(pos.x / iconContainer.cellWidth);
                var row = Math.floor(pos.y / iconContainer.cellHeight);
                var gridIdx = col * iconContainer.maxRows + row;
                var destDir = DesktopService.desktopDir;

                if (col >= 0 && row >= 0 && gridIdx >= 0 && gridIdx < DesktopService.items.count) {
                    var item = DesktopService.items.get(gridIdx);
                    if (item && item.type === "folder" && !item.isPlaceholder) {
                        destDir = item.path;
                    }
                }

                DesktopService.importFiles(drop.urls, destDir);
                drop.acceptProposedAction();
            }
        }

        // Rubber-band selection
        Rectangle {
            id: selectionRect
            z: 6
            visible: false
            color: "transparent"
            border.color: Styling.srItem("overprimary")
            border.width: 2
            Rectangle {
                anchors.fill: parent
                color: Styling.srItem("overprimary")
                opacity: 0.15
            }
        }

        MouseArea {
            id: selectionArea
            anchors.fill: parent
            z: 5
            cursorShape: Qt.ArrowCursor
            property point startPoint: Qt.point(0, 0)
            property bool dragging: false

            onPressed: mouse => {
                // Only start rubber-band on empty grid cells
                var col = Math.floor(mouse.x / iconContainer.cellWidth);
                var row = Math.floor(mouse.y / iconContainer.cellHeight);
                var gridIdx = col * iconContainer.maxRows + row;
                if (col >= 0 && row >= 0 && gridIdx >= 0 && gridIdx < DesktopService.items.count) {
                    var item = DesktopService.items.get(gridIdx);
                    if (item && !item.isPlaceholder) {
                        // Click is on an icon — pass through
                        mouse.accepted = false;
                        return;
                    }
                }

                startPoint = Qt.point(mouse.x, mouse.y);
                selectionRect.x = mouse.x;
                selectionRect.y = mouse.y;
                selectionRect.width = 0;
                selectionRect.height = 0;
                selectionRect.visible = false;
                dragging = false;
            }

            onPositionChanged: mouse => {
                if (!dragging) {
                    var dx = mouse.x - startPoint.x;
                    var dy = mouse.y - startPoint.y;
                    if (Math.abs(dx) < 5 && Math.abs(dy) < 5) return;
                    dragging = true;
                    selectionRect.visible = true;
                }
                var x = Math.min(startPoint.x, mouse.x);
                var y = Math.min(startPoint.y, mouse.y);
                var w = Math.abs(startPoint.x - mouse.x);
                var h = Math.abs(startPoint.y - mouse.y);
                selectionRect.x = x;
                selectionRect.y = y;
                selectionRect.width = w;
                selectionRect.height = h;
            }

            onReleased: mouse => {
                selectionRect.visible = false;
                if (dragging && selectionRect.width > 10 && selectionRect.height > 10) {
                    // Rubber-band selection: select all icons that intersect
                    var arr = (mouse.modifiers & Qt.ControlModifier) ? iconContainer.selectedIndices.slice() : [];
                    for (var i = 0; i < DesktopService.items.count; i++) {
                        var item = DesktopService.items.get(i);
                        if (!item || item.isPlaceholder || item.type === "trash") continue;
                        var ix = Math.floor(i / iconContainer.maxRows) * iconContainer.cellWidth;
                        var iy = (i % iconContainer.maxRows) * iconContainer.cellHeight;
                        var iw = iconContainer.cellWidth * 0.7;
                        var ih = iconContainer.cellHeight * 0.7;
                        ix = ix + (iconContainer.cellWidth - iw) / 2;
                        iy = iy + 8;
                        // Check intersection
                        if (selectionRect.x < ix + iw && selectionRect.x + selectionRect.width > ix &&
                            selectionRect.y < iy + ih && selectionRect.y + selectionRect.height > iy) {
                            var pos = arr.indexOf(i);
                            if (pos < 0) arr.push(i);
                        }
                    }
                    iconContainer.selectedIndices = arr;
                } else if (!dragging) {
                    // Single click on empty space
                    iconContainer.clearSelection();
                }
                dragging = false;
            }
        }

        // Background right-click context menu
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: (eventPoint) => {
                if (iconContainer._iconMenuOpen) {
                    iconContainer._iconMenuOpen = false;
                    return;
                }
                // Don't show background menu when clicking on an icon
                var pos = eventPoint.position;
                var col = Math.floor(pos.x / iconContainer.cellWidth);
                var row = Math.floor(pos.y / iconContainer.cellHeight);
                iconContainer._pasteCol = col;
                iconContainer._pasteRow = row;
                var gridIdx = col * iconContainer.maxRows + row;
                if (gridIdx >= 0 && gridIdx < DesktopService.items.count) {
                    var item = DesktopService.items.get(gridIdx);
                    if (item && !item.isPlaceholder) return;
                }

                var menuItems = [
                    {
                        text: "New Folder",
                        icon: Icons.folder,
                        isSeparator: false,
                        onTriggered: function () {
                            DesktopService.addPlaceholder("folder", "folder", iconContainer._pasteCol, iconContainer._pasteRow);
                            iconContainer._pendingEditIdx = iconContainer._pasteCol * iconContainer.maxRows + iconContainer._pasteRow;
                            iconContainer._pendingEditType = "folder";
                        }
                    },
                    {
                        text: "New File",
                        icon: Icons.file,
                        isSeparator: false,
                        onTriggered: function () {
                            DesktopService.addPlaceholder("file", "text-x-generic", iconContainer._pasteCol, iconContainer._pasteRow);
                            iconContainer._pendingEditIdx = iconContainer._pasteCol * iconContainer.maxRows + iconContainer._pasteRow;
                            iconContainer._pendingEditType = "file";
                        }
                    }
                ];

                if (DesktopService.copiedPath) {
                    menuItems.push({
                        isSeparator: true,
                        text: ""
                    });
                    menuItems.push({
                        text: "Paste",
                        icon: Icons.clip,
                        isSeparator: false,
                        onTriggered: function () {
                            DesktopService.pasteFile(DesktopService.desktopDir, iconContainer._pasteCol, iconContainer._pasteRow);
                        }
                    });
                }

                menuItems.push({
                    isSeparator: true,
                    text: ""
                });
                menuItems.push({
                    text: "Refresh",
                    icon: Icons.sync,
                    isSeparator: false,
                    onTriggered: function () {
                        DesktopService.scanDesktop();
                    }
                });
                menuItems.push({
                    text: "Open in Terminal",
                    icon: Icons.terminal,
                    isSeparator: false,
                    onTriggered: function () {
                        var escapedDir = DesktopService.desktopDir.replace(/'/g, "'\\''");
                        DesktopService.runInActiveWorkspace("env RETRO_CWD='" + escapedDir + "' retro app terminal open");
                    }
                });
                menuItems.push({
                    isSeparator: true,
                    text: ""
                });
                menuItems.push({
                    text: iconContainer.selectedIndices.length > 0 ? "Deselect All" : "Select All",
                    icon: Icons.squaresFour,
                    isSeparator: false,
                    onTriggered: function () {
                        if (iconContainer.selectedIndices.length > 0) iconContainer.clearSelection();
                        else iconContainer.selectAll();
                    }
                });

                // ── Widgets section ──
                menuItems.push({ isSeparator: true, text: "" });
                menuItems.push({
                    text: (Config.desktop.editMode ? "Disable" : "Enable") + " Edit Mode",
                    icon: Icons.edit,
                    isSeparator: false,
                    onTriggered: function () {
                        Config.desktop.editMode = !Config.desktop.editMode;
                    }
                });
                menuItems.push({
                    text: (Config.desktop.showIcons ? "Hide" : "Show") + " Desktop Icons",
                    icon: Icons.squaresFour,
                    isSeparator: false,
                    onTriggered: function () {
                        Config.desktop.showIcons = !Config.desktop.showIcons;
                    }
                });

                Visibilities.contextMenu.openCustomMenu(menuItems, 260, 32, "desktop");
            }
        }

        Repeater {
            model: DesktopService.items

            delegate: Item {
                id: delegateRoot
                required property string name
                required property string path
                required property string type
                required property string icon
                required property bool isDesktopFile
                required property bool isPlaceholder
                required property int index
                property int gridX: Math.floor(index / iconContainer.maxRows)
                property int gridY: index % iconContainer.maxRows

                width: iconContainer.cellWidth
                height: iconContainer.cellHeight

                x: Math.floor(index / iconContainer.maxRows) * iconContainer.cellWidth
                y: (index % iconContainer.maxRows) * iconContainer.cellHeight

                visible: !isPlaceholder

                Behavior on x {
                    enabled: !dragHandler.active && Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on y {
                    enabled: !dragHandler.active && Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutCubic
                    }
                }

                DesktopIcon {
                    id: iconItem
                    anchors.fill: parent

                    itemName: delegateRoot.name
                    itemPath: delegateRoot.path
                    itemType: delegateRoot.type
                    itemIcon: delegateRoot.icon
                    isDesktopFile: delegateRoot.isDesktopFile

                    selected: delegateRoot.index >= 0 && iconContainer.selectedIndices.indexOf(delegateRoot.index) >= 0

                    TapHandler {
                        id: singleTapHandler
                        acceptedButtons: Qt.LeftButton
                        gesturePolicy: TapHandler.DragThreshold
                        onTapped: { iconTapTimer.restart(); }
                    }

                    Timer {
                        id: iconTapTimer
                        interval: 200
                        onTriggered: {
                            if (!iconItem.editMode) iconItem.singleClicked();
                        }
                    }

                    onEditCommitted: function (newName) {
                        iconContainer._editActive = false;
                        if (iconItem.isNewItem) {
                            var type = iconContainer._pendingEditType || "file";
                            var newPath = DesktopService.desktopDir + "/" + newName;
                            DesktopService.updateIconPosition(newPath, delegateRoot.gridX, delegateRoot.gridY);
                            DesktopService.createNew(type, DesktopService.desktopDir, newName);
                            DesktopService.clearPlaceholder(delegateRoot.index);
                            iconContainer._pendingEditIdx = -1;
                            iconContainer._pendingEditType = "";
                        } else {
                            DesktopService.renameFile(delegateRoot.path, newName);
                        }
                    }

                    onEditCancelled: function () {
                        iconContainer._editActive = false;
                        if (iconItem.isNewItem) {
                            DesktopService.clearPlaceholder(delegateRoot.index);
                            iconContainer._pendingEditIdx = -1;
                            iconContainer._pendingEditType = "";
                        }
                    }

                    onSingleClicked: {
                        iconContainer.toggleSelection(delegateRoot.index, false);
                    }

                    Timer {
                        id: pendingEditTimer
                        interval: 50
                        running: delegateRoot.index === iconContainer._pendingEditIdx && !iconItem.editMode
                        onTriggered: {
                            iconItem.isNewItem = true;
                            iconItem.startEdit("", true);
                            iconContainer._editActive = true;
                        }
                    }

                    onActivated: {
                        console.log("Activated:", itemName);
                    }

                    onContextMenuRequested: {
                        console.log("Context menu requested for:", itemName, "type:", delegateRoot.type);
                        iconContainer._iconMenuOpen = true;
                        var items = [];
                        var isSelected = iconContainer.selectedIndices.indexOf(delegateRoot.index) >= 0;
                        var isBulk = isSelected && iconContainer.selectedIndices.length > 1;

                        if (delegateRoot.type === "trash") {
                            items = [
                                { text: "Open Trash", icon: Icons.launch, isSeparator: false,
                                  onTriggered: function () { DesktopService.openTrash(); } }
                            ];
                            if (DesktopService.trashHasItems) {
                                items.push({ isSeparator: true, text: "" });
                                items.push({ text: "Empty Trash", icon: Icons.trash,
                                  textColor: Colors.overError, highlightColor: Colors.error, isSeparator: false,
                                  onTriggered: function () { DesktopService.emptyTrash(); } });
                            }
                        } else if (isBulk) {
                            var count = iconContainer.selectedIndices.length;
                            items = [
                                { text: "Open All (" + count + ")", icon: Icons.launch, isSeparator: false,
                                  onTriggered: function () { DesktopService.bulkOpen(iconContainer.selectedIndices); } },
                                { isSeparator: true, text: "" },
                                { text: "Move to Trash (" + count + ")", icon: Icons.trash,
                                  textColor: Colors.overError, highlightColor: Colors.error, isSeparator: false,
                                  onTriggered: function () { DesktopService.bulkTrash(iconContainer.selectedIndices); iconContainer.clearSelection(); } }
                            ];
                        } else {
                            items = [
                                { text: "Open", icon: Icons.launch, isSeparator: false,
                                  onTriggered: function () {
                                    if (delegateRoot.isDesktopFile) DesktopService.executeDesktopFile(delegateRoot.path);
                                    else DesktopService.openFile(delegateRoot.path);
                                  } },
                                { text: "Open in Terminal", icon: Icons.terminal, isSeparator: false,
                                  onTriggered: function () {
                                    var target = delegateRoot.path;
                                    var dir = delegateRoot.type === "folder" ? target : target.substring(0, target.lastIndexOf("/"));
                                    var escapedDir = dir.replace(/'/g, "'\\''");
                                    DesktopService.runInActiveWorkspace("env RETRO_CWD='" + escapedDir + "' retro app terminal open");
                                  } },
                                { isSeparator: true, text: "" },
                                { text: "Copy", icon: Icons.copy, isSeparator: false,
                                  onTriggered: function () { DesktopService.copyFilePath(delegateRoot.path); } },
                                { text: "Rename", icon: Icons.edit, isSeparator: false,
                                                                      onTriggered: function () { iconContainer._editActive = true; iconItem.startEdit(delegateRoot.name, false); } },
                                { isSeparator: true, text: "" },
                                { text: "Properties", icon: Icons.info, isSeparator: false,
                                  onTriggered: function () { DesktopService.showProperties(delegateRoot.path); } },
                                { isSeparator: true, text: "" },
                                { text: "Delete", icon: Icons.trash,
                                  textColor: Colors.overError, highlightColor: Colors.error, isSeparator: false,
                                  onTriggered: function () { DesktopService.trashFile(delegateRoot.path); DesktopService.refreshTrash(); } }
                            ];
                        }
                        Visibilities.contextMenu.openCustomMenu(items, 260, 32, "desktop");
                    }

                    opacity: dragHandler.active ? 0.3 : 1.0

                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration / 2
                            easing.type: Easing.OutCubic
                        }
                    }

                    DragHandler {
                        id: dragHandler
                        target: dragPreview
                        onActiveChanged: {
                            // Cancel inline edit if user starts dragging the placeholder
                            if (active && (delegateRoot.type === "placeholder-new" || iconItem.editMode)) {
                                iconItem.cancelEdit();
                                iconContainer._editActive = false;
                            }
                            if (!active) {
                                var targetIndex = delegateRoot.index;

                                console.log("Drop - Drag.target:", dragPreview.Drag.target);

                                if (dragPreview.Drag.target && dragPreview.Drag.target.visualIndex !== undefined) {
                                    targetIndex = dragPreview.Drag.target.visualIndex;
                                    console.log("Using Drag.target visualIndex:", targetIndex);
                                } else {
                                    var gridPos = iconContainer.mapFromItem(dragPreview.parent, dragPreview.x, dragPreview.y);
                                    var dropX = gridPos.x + dragPreview.width / 2;
                                    var dropY = gridPos.y + dragPreview.height / 2;

                                    if (dropX >= 0 && dropY >= 0 && dropX < iconContainer.width && dropY < iconContainer.height) {
                                        var col = Math.floor(dropX / iconContainer.cellWidth);
                                        var row = Math.floor(dropY / iconContainer.cellHeight);

                                        col = Math.max(0, Math.min(col, iconContainer.maxColumns - 1));
                                        row = Math.max(0, Math.min(row, iconContainer.maxRows - 1));

                                        targetIndex = col * iconContainer.maxRows + row;
                                        console.log("Calculated targetIndex:", targetIndex, "col:", col, "row:", row);
                                    }
                                }

                                if (targetIndex !== delegateRoot.index) {
                                    var isBulk = iconContainer.selectedIndices.indexOf(delegateRoot.index) >= 0
                                                 && iconContainer.selectedIndices.length > 1;
                                    // If dropping onto a folder, move the file INTO it (single item only)
                                    if (!isBulk && targetIndex >= 0 && targetIndex < DesktopService.items.count) {
                                        var targetItem = DesktopService.items.get(targetIndex);
                                        if (targetItem && targetItem.type === "folder" && !targetItem.isPlaceholder && delegateRoot.path !== "trash:///virtual") {
                                            console.log("Moving", delegateRoot.path, "into folder", targetItem.path);
                                            DesktopService.moveToFolder(delegateRoot.path, targetItem.path);
                                            iconContainer._pendingEditIdx = -1;
                                            dragPreview.Drag.drop();
                                            return;
                                        }
                                    }
                                    console.log("Moving from", delegateRoot.index, "to", targetIndex);
                                    var isBulkDrag = iconContainer.selectedIndices.indexOf(delegateRoot.index) >= 0
                                                     && iconContainer.selectedIndices.length > 1;
                                    if (isBulkDrag) {
                                        DesktopService.bulkMove(iconContainer.selectedIndices, targetIndex);
                                    } else {
                                        DesktopService.moveItem(delegateRoot.index, targetIndex);
                                    }

                                    // Follow placeholder-new items to their new position
                                    if (!active && delegateRoot.type === "placeholder-new") {
                                        iconContainer._pendingEditIdx = targetIndex;
                                    }
                                }

                                dragPreview.Drag.drop();
                            }
                        }
                    }
                }

                Item {
                    id: dragPreview
                    parent: iconContainer
                    width: delegateRoot.width
                    height: delegateRoot.height
                    visible: dragHandler.active
                    z: 999

                    // Stacked ghost icons for bulk drag — preserve relative grid positions
                    Repeater {
                        model: iconContainer.selectedIndices.indexOf(delegateRoot.index) >= 0
                               && iconContainer.selectedIndices.length > 1
                               ? iconContainer.selectedIndices : []
                        delegate: Item {
                            property int stackIdx: modelData
                            property int stackPos: iconContainer.selectedIndices.indexOf(stackIdx)
                            // Compute relative offset from the dragged icon's grid position
                            property int relCol: {
                                if (stackIdx < 0 || stackIdx >= DesktopService.items.count) return 0;
                                var it = DesktopService.items.get(stackIdx);
                                if (!it) return 0;
                                return (it.gridX || 0) - delegateRoot.gridX;
                            }
                            property int relRow: {
                                if (stackIdx < 0 || stackIdx >= DesktopService.items.count) return 0;
                                var it = DesktopService.items.get(stackIdx);
                                if (!it) return 0;
                                return (it.gridY || 0) - delegateRoot.gridY;
                            }
                            x: relCol * iconContainer.cellWidth
                            y: relRow * iconContainer.cellHeight
                            z: 999 - stackPos
                            width: dragPreview.width
                            height: dragPreview.height
                            opacity: 0.85
                            visible: stackIdx >= 0 && stackIdx < DesktopService.items.count
                            DesktopIcon {
                                anchors.fill: parent
                                itemName: DesktopService.items.get(stackIdx) ? DesktopService.items.get(stackIdx).name : ""
                                itemPath: DesktopService.items.get(stackIdx) ? DesktopService.items.get(stackIdx).path : ""
                                itemType: DesktopService.items.get(stackIdx) ? DesktopService.items.get(stackIdx).type : "file"
                                itemIcon: DesktopService.items.get(stackIdx) ? DesktopService.items.get(stackIdx).icon : ""
                                isDesktopFile: DesktopService.items.get(stackIdx) ? DesktopService.items.get(stackIdx).isDesktopFile : false
                                opacity: 0.7
                                scale: 1.05
                            }
                        }
                    }

                    // Single item drag (fallback when not bulk)
                    DesktopIcon {
                        anchors.fill: parent
                        itemName: delegateRoot.name
                        itemPath: delegateRoot.path
                        itemType: delegateRoot.type
                        itemIcon: delegateRoot.icon
                        isDesktopFile: delegateRoot.isDesktopFile
                        opacity: 0.7
                        scale: 1.05
                        visible: !(iconContainer.selectedIndices.indexOf(delegateRoot.index) >= 0
                                    && iconContainer.selectedIndices.length > 1)
                    }

                    Drag.active: dragHandler.active
                    Drag.source: delegateRoot
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2
                    Drag.keys: ["desktopIcon"]
                }

                DropArea {
                    anchors.fill: parent
                    keys: ["desktopIcon"]

                    property int visualIndex: delegateRoot.index

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.color: Styling.srItem("overprimary")
                        border.width: 2
                        radius: Styling.radius(0) / 2
                        visible: parent.containsDrag
                        opacity: 0.5
                    }
                }
            }
        }
    }

    // Floating desktop widget layer (above icons, below bar)
    DesktopWidgets {
        id: desktopWidgets
        anchors.fill: parent
        z: 50
    }

    Rectangle {
        anchors.centerIn: parent
        width: 200
        height: 60
        color: Qt.rgba(0, 0, 0, 0.7)
        radius: Styling.radius(0)
        visible: Config.desktop.showIcons && !DesktopService.initialLoadComplete

        Text {
            anchors.centerIn: parent
            text: "Loading desktop..."
            color: "white"
            font.family: Config.defaultFont
            font.pixelSize: Styling.fontSize(0)
        }
    }
}

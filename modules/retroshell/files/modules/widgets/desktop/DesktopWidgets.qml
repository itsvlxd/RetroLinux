import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.config
import qs.modules.widgets.desktop

// Floating desktop widget layer. Renders each enabled widget as a draggable
// card positioned by its saved normalized coordinates. Widget data lives in
// its own config file (desktop_widgets.json) read/written with manual JSON so
// it is not subject to JsonAdapter array-loading limitations. In edit mode the
// user can drag widgets around and positions persist back to the file.
Item {
    id: root

    anchors.fill: parent

    Connections {
        target: Config.desktop
        function onEditModeChanged() {
            console.log("[DesktopWidgets] editMode changed to", Config.desktop.editMode);
        }
    }

    // ── Widget config file ──
    readonly property string widgetsFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/retro/shell/desktop_widgets.json"

    // Loaded widgets: [{id, type, x, y, width, height}] (x/y normalized 0..1)
    property var widgets: []
    readonly property var widgetOrder: root.widgets.map(function (w) { return w.id; })
    // Whether any widgets are present (used to activate the desktop layer).
    readonly property bool hasWidgets: root.widgets.length > 0

    FileView {
        id: widgetsFileView
        path: root.widgetsFile
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onLoaded: root.parseWidgets(text())
        onFileChanged: reload()
    }

    function parseWidgets(raw) {
        var list = [];
        if (raw && raw.trim().length > 0) {
            try {
                var data = JSON.parse(raw);
                if (data && Array.isArray(data.widgets)) {
                    list = data.widgets;
                }
            } catch (e) {
                console.warn("[DesktopWidgets] parse error:", e);
            }
        }
        // Only reassign when the content actually changed, so the Repeater
        // does not recreate delegates on every identical file reload.
        if (JSON.stringify(list) !== JSON.stringify(root.widgets)) {
            root.widgets = list;
        }
    }

    function saveWidgets() {
        widgetsFileView.setText(JSON.stringify({ "widgets": root.widgets }, null, 2));
    }

    // ── Catalog of widget types available to add ──
    // type -> {label, icon}. Extend to add more widget types.
    readonly property var widgetCatalog: ({
        "calendar": { label: "Calendar 4x4", icon: Icons.clock },
        "calendar2x4": { label: "Calendar 2x4", icon: Icons.clock },
        "weather": { label: "Weather Widget", icon: Icons.sun },
        "weather2x4": { label: "Weather 2x4", icon: Icons.sun },
        "weather2x2": { label: "Weather 2x2", icon: Icons.sun },
        "music2x2": { label: "Music Player 2x2", icon: Icons.player },
        "music2x4": { label: "Music Player 2x4", icon: Icons.player },
        "clockdigital": { label: "Digital Clock", icon: Icons.clock },
        "clockanalog": { label: "Analog Clock", icon: Icons.clock },
        "worldclock": { label: "World Clock", icon: Icons.clock },
        "storage": { label: "Device Storage", icon: Icons.disk },
        "sysmonitor": { label: "System Monitor", icon: Icons.cpu },
        "battery": { label: "Battery", icon: Icons.batteryFull }
    })

    // Look up a widget's data entry by id.
    function widgetDataById(id) {
        for (var i = 0; i < root.widgets.length; i++) {
            if (root.widgets[i].id === id)
                return root.widgets[i];
        }
        return null;
    }

    // Map a widget type to a component. Extend to add more widget types.
    function componentForType(type) {
        switch (type) {
        case "calendar": return calendarComponent;
        case "calendar2x4": return calendarComponent;
        case "weather": return weatherComponent;
        case "weather2x4": return weather2x4Component;
        case "weather2x2": return weather2x2Component;
        case "music2x2": return music2x2Component;
        case "music2x4": return music2x4Component;
        case "clockdigital": return clockDigitalComponent;
        case "clockanalog": return clockAnalogComponent;
        case "worldclock": return worldClockComponent;
        case "storage": return storageComponent;
        case "sysmonitor": return sysMonitorComponent;
        case "battery": return batteryComponent;
        }
        return null;
    }

    function widgetSizeFor(type) {
        switch (type) {
        case "calendar": return [320, 320];
        case "calendar2x4": return [320, 160];
        case "weather": return [320, 240];
        case "weather2x4": return [320, 160];
        case "weather2x2": return [160, 160];
        case "music2x2": return [160, 160];
        case "music2x4": return [320, 160];
        case "clockdigital": return [160, 160];
        case "clockanalog": return [160, 160];
        case "worldclock": return [320, 80];
        case "storage": return [160, 160];
        case "sysmonitor": return [160, 160];
        case "battery": return [160, 160];
        }
        return [280, 240];
    }

    // Copy a widget entry, preserving optional fields (face, timezones, etc.)
    function cloneWidgetEntry(w) {
        var e = {
            id: w.id,
            type: w.type,
            x: w.x,
            y: w.y,
            width: w.width,
            height: w.height,
            locked: w.locked === true
        };
        if (w.face !== undefined) e.face = w.face;
        if (w.timezones !== undefined) e.timezones = w.timezones;
        return e;
    }

    // Persist an updated (x,y) for a widget id.
    function updateWidgetPosition(id, nx, ny) {
        var list = root.widgets.slice();
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id) {
                var e = root.cloneWidgetEntry(list[i]);
                e.x = nx;
                e.y = ny;
                list[i] = e;
                break;
            }
        }
        root.widgets = list;
        root.saveWidgets();
    }

    // Persist a lock state change for a widget id.
    function updateWidgetLock(id, locked) {
        var list = root.widgets.slice();
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id) {
                var e = root.cloneWidgetEntry(list[i]);
                e.locked = locked === true;
                list[i] = e;
                break;
            }
        }
        root.widgets = list;
        root.saveWidgets();
    }

    // Persist a face/style change for a widget id (clocks).
    function updateWidgetFace(id, face) {
        var list = root.widgets.slice();
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id) {
                var e = root.cloneWidgetEntry(list[i]);
                e.face = face;
                list[i] = e;
                break;
            }
        }
        root.widgets = list;
        root.saveWidgets();
    }

    function lockAll(locked) {
        var list = root.widgets.slice();
        for (var i = 0; i < list.length; i++) {
            var e = root.cloneWidgetEntry(list[i]);
            e.locked = locked === true;
            list[i] = e;
        }
        root.widgets = list;
        root.saveWidgets();
    }

    function removeWidget(id) {
        root.widgets = root.widgets.filter(function (w) { return w.id !== id; });
        root.saveWidgets();
    }

    // Add a widget of the given type at a normalized position (or center).
    function addWidget(type, nx, ny) {
        if (root.widgetOrder.indexOf(type) !== -1)
            return;
        var size = root.widgetSizeFor(type);
        var list = root.widgets.slice();
        list.push({
            id: type,
            type: type,
            x: (nx !== undefined && nx !== null) ? nx : 0.5,
            y: (ny !== undefined && ny !== null) ? ny : 0.5,
            width: size[0],
            height: size[1],
            locked: false
        });
        root.widgets = list;
        root.saveWidgets();
    }

    // Widget management context menu (right-click on the desktop).
    function openWidgetMenu() {
        var items = [];
        var order = root.widgetOrder;

        items.push({
            text: (Config.desktop.editMode ? "Disable" : "Enable") + " Edit Mode",
            icon: Icons.edit,
            isSeparator: false,
            onTriggered: function () {
                Config.desktop.editMode = !Config.desktop.editMode;
            }
        });
        items.push({
            text: (Config.desktop.showIcons ? "Hide" : "Show") + " Desktop Icons",
            icon: Icons.squaresFour,
            isSeparator: false,
            onTriggered: function () {
                Config.desktop.showIcons = !Config.desktop.showIcons;
            }
        });

        if (order.length > 0) {
            items.push({ isSeparator: true, text: "" });
            items.push({
                text: "Lock All Widgets",
                icon: Icons.lock,
                isSeparator: false,
                onTriggered: function () {
                    root.lockAll(true);
                }
            });
            items.push({
                text: "Unlock All Widgets",
                icon: Icons.unpin,
                isSeparator: false,
                onTriggered: function () {
                    root.lockAll(false);
                }
            });
        }

        Visibilities.contextMenu.openCustomMenu(items, 260, 32, "desktop");
    }

    Repeater {
        model: root.widgetOrder

        delegate: Item {
            id: witem
            required property string modelData

            readonly property var entry: root.widgetDataById(modelData)

            // Working position, updated live while dragging and initialized
            // from the saved entry when the delegate is created.
            property real curX: entry && entry.x !== undefined ? entry.x : 0.5
            property real curY: entry && entry.y !== undefined ? entry.y : 0.5

            visible: entry !== null
            width: entry && entry.width ? entry.width : 280
            height: entry && entry.height ? entry.height : 240

            x: (curX * root.width) - width / 2
            y: (curY * root.height) - height / 2

            Loader {
                anchors.fill: parent
                sourceComponent: root.componentForType(entry ? entry.type : "")

                onLoaded: {
                    if (item) {
                        // Keep the widget's data in sync: the entry can change
                        // live (settings updates face/timezones/etc.) without
                        // the delegate being recreated, so bind instead of
                        // assigning once.
                        item.widgetLayer = root;
                        function syncWidgetData() {
                            item.widgetData = witem.entry;
                        }
                        syncWidgetData();
                        witem.entryChanged.connect(syncWidgetData);
                        // Live visual move only — no file write per frame.
                        item.positionChanged.connect(function (nx, ny) {
                            witem.curX = nx;
                            witem.curY = ny;
                        });
                        // Commit once on release.
                        item.positionCommitted.connect(function (nx, ny) {
                            root.updateWidgetPosition(witem.modelData, nx, ny);
                        });
                        item.lockToggled.connect(function (newLocked) {
                            root.updateWidgetLock(witem.modelData, newLocked);
                        });
                        if (item.faceSelected) {
                            item.faceSelected.connect(function (face) {
                                root.updateWidgetFace(witem.modelData, face);
                            });
                        }
                        item.requestRemove.connect(function () {
                            root.removeWidget(witem.modelData);
                        });
                    }
                }
            }
        }
    }

    // Right-click on the desktop opens the widget management menu.
    // Only active when icons are hidden, so it doesn't override the icon
    // background menu (which also contains the widget items when icons show).
    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: !Config.desktop.showIcons
        onTapped: root.openWidgetMenu()
    }

    Component {
        id: calendarComponent
        CalendarWidget {}
    }

    Component {
        id: weatherComponent
        WeatherWidget {}
    }

    Component {
        id: weather2x4Component
        WeatherWidget2x4 {}
    }

    Component {
        id: weather2x2Component
        WeatherWidget2x2 {}
    }

    Component {
        id: music2x2Component
        MusicPlayer2x2 {}
    }

    Component {
        id: music2x4Component
        MusicPlayer2x4 {}
    }

    Component {
        id: clockDigitalComponent
        ClockDigitalWidget {}
    }

    Component {
        id: clockAnalogComponent
        ClockAnalogWidget {}
    }

    Component {
        id: worldClockComponent
        WorldClockWidget {}
    }

    Component {
        id: storageComponent
        StorageWidget {}
    }

    Component {
        id: sysMonitorComponent
        SystemMonitorWidget {}
    }

    Component {
        id: batteryComponent
        BatteryWidget {}
    }

    // Hint shown when in edit mode with no widgets yet.
    Rectangle {
        anchors.centerIn: parent
        width: 360
        height: 60
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.6)
        visible: Config.desktop.editMode && root.widgetOrder.length === 0

        Text {
            anchors.centerIn: parent
            text: "No widgets yet — right-click the desktop to add one"
            color: "white"
            font.family: Config.defaultFont
            font.pixelSize: 14
        }
    }

    Component.onCompleted: {
        widgetsFileView.reload();
    }
}
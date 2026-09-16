pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var focusedMonitor: null
    property var focusedWorkspace: null
    property var focusedClient: null

    property int focusHistoryCounter: 0
    property string _lineBuffer: ""

    property QtObject clients: QtObject {
        property var values: []
    }

    property QtObject monitors: QtObject {
        property var values: []
    }

    property QtObject workspaces: QtObject {
        property var values: []
    }

    signal rawEvent(var event)

    // Config path for axctl daemon
    property string configPath: (Quickshell.env("HOME") + "/.config/retro/shellctl.toml")

    function dispatch(command) {
        if (!command) return;

        let spaceIdx = command.indexOf(' ');
        let action = spaceIdx !== -1 ? command.substring(0, spaceIdx).trim() : command.trim();
        let rawArgs = spaceIdx !== -1 ? command.substring(spaceIdx + 1).trim() : "";

        let getAddr = (str) => {
            let m = str.match(/address:([^\s,]+)/);
            return m ? m[1] : str.trim();
        };

        let hyprCmd = "";
        if (action === "workspace") {
            hyprCmd = "hl.dsp.focus({ workspace = " + rawArgs + " })";
        } else if (action === "closewindow") {
            hyprCmd = "hl.dsp.window.close({ window = address:0x" + getAddr(rawArgs) + " })";
        } else if (action === "focuswindow") {
            hyprCmd = "hl.dsp.focus({ window = address:0x" + getAddr(rawArgs) + " })";
        } else if (action === "movetoworkspacesilent") {
            let subParts = rawArgs.split(',');
            let wsId = subParts[0].trim();
            let addr = subParts.length > 1 ? getAddr(subParts[1]) : "";
            hyprCmd = "hl.dsp.window.move({ workspace = " + wsId + ", window = address:0x" + addr + " })";
        } else if (action === "focusmonitor") {
            hyprCmd = "hl.dsp.focus({ monitor = '" + rawArgs + "' })";
        } else if (action === "togglespecialworkspace") {
            hyprCmd = "hl.dsp.workspace.toggle_special('" + (rawArgs || "") + "')";
        } else if (action === "fullscreen") {
            hyprCmd = "hl.dsp.window.fullscreen({})";
        } else if (action === "exit") {
            hyprCmd = "hl.dsp.exit()";
        } else {
            hyprCmd = "hl.dsp.exec_cmd('" + command.replace(/'/g, "'\\''") + "')";
        }

        let proc = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        proc.command = ["hyprctl", "dispatch", hyprCmd];
        proc.onExited.connect(() => proc.destroy());
        proc.running = true;
    }

    function monitorFor(screen) {
        if (!screen) return null;
        let screenName = screen.name || screen;
        let values = root.monitors.values || [];
        // Exact match
        for (let i = 0; i < values.length; i++) {
            if (values[i].name === screenName) return values[i];
        }
        // Case-insensitive match
        let lower = screenName.toLowerCase();
        for (let i = 0; i < values.length; i++) {
            if (values[i].name && values[i].name.toLowerCase() === lower) return values[i];
        }
        // Fallback: match by screen index position
        let screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; i++) {
            if (screens[i] === screen || (screens[i] && screens[i].name === screenName)) {
                if (i < values.length) return values[i];
                break;
            }
        }
        return null;
    }

    function applyState(state) {
        if (!state) return;

        // --- Windows ---
        if (state.windows) {
            let existingClients = root.clients.values || [];
            let mappedClients = state.windows.map(win => {
                let existing = existingClients.find(c => c.address === win.id);
                let prevFocus = existing && existing.focusHistoryID !== undefined ? existing.focusHistoryID : 999999;
                let newFocus = win.is_focused ? (existing && existing.is_focused ? prevFocus : --root.focusHistoryCounter) : prevFocus;
                return {
                    address: win.id,
                    class: win.app_id,
                    title: win.title,
                    workspace: { id: parseInt(win.workspace_id) || 0, name: win.workspace_id },
                    monitor: parseInt(win.metadata ? win.metadata.monitor_id : 0) || 0,
                    floating: win.is_floating,
                    fullscreen: win.is_fullscreen,
                    hidden: win.is_hidden,
                    mapped: true,
                    at: [win.metadata ? (win.metadata.x || 0) : 0, win.metadata ? (win.metadata.y || 0) : 0],
                    size: [win.metadata ? (win.metadata.width || 100) : 100, win.metadata ? (win.metadata.height || 100) : 100],
                    xwayland: (win.metadata ? win.metadata.xwayland : false) || false,
                    is_focused: win.is_focused || false,
                    focusHistoryID: newFocus
                };
            });
            root.clients.values = mappedClients;
            let focused = mappedClients.find(w => w.address === (root.focusedClient ? root.focusedClient.address : undefined)) || mappedClients.find(w => w.is_focused) || null;
            if (focused !== root.focusedClient) {
                root.focusedClient = focused;
            }
        }

        // --- Workspaces ---
        if (state.workspaces) {
            let mappedWorkspaces = state.workspaces.map(ws => ({
                id: parseInt(ws.id) || 0,
                name: ws.name,
                monitor: ws.monitor_id,
                active: ws.is_active,
                windows: 0
            }));
            root.workspaces.values = mappedWorkspaces;
            let focused = mappedWorkspaces.find(ws => ws.active) || null;
            if (focused !== root.focusedWorkspace) {
                root.focusedWorkspace = focused;
            }
        }

        // Build name→id lookup for workspace names (axctl may report active_workspace as name, not ID)
        let wsNameToId = {};
        let wsList = root.workspaces.values || [];
        for (let i = 0; i < wsList.length; i++) {
            wsNameToId[wsList[i].name] = wsList[i].id;
        }

        // --- Monitors ---
        if (state.monitors) {
            let mappedMonitors = state.monitors.map(mon => {
                let rawWs = mon.metadata ? mon.metadata.active_workspace : "";
                let wsId = parseInt(rawWs) || wsNameToId[rawWs] || 0;
                return {
                    id: parseInt(mon.id) || 0,
                    name: mon.name,
                    focused: mon.is_focused,
                    width: mon.width,
                    height: mon.height,
                    refreshRate: mon.refresh_rate,
                    scale: mon.scale,
                    x: parseInt(mon.metadata ? mon.metadata.x : 0) || 0,
                    y: parseInt(mon.metadata ? mon.metadata.y : 0) || 0,
                    transform: parseInt(mon.metadata ? mon.metadata.transform : 0) || 0,
                    activeWorkspace: { id: wsId, name: rawWs }
                };
            });
            root.monitors.values = mappedMonitors;
            let focused = mappedMonitors.find(m => m.focused) || null;
            if (focused !== root.focusedMonitor) {
                root.focusedMonitor = focused;
            }
        }
    }

    property Process ensureConfigDir: Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.config/retro"]
        running: true
    }

    property Process axctlProcess: Process {
        command: ["axctl", "-c", root.configPath, "daemon"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                // Daemon logs can be printed here if needed
            }
        }
        onExited: (code) => {
            console.warn("axctl daemon exited with code:", code)
        }
    }

    // Brief delay to let daemon start before subscribing
    Timer {
        id: subscribeDelay
        interval: 500
        running: true
        onTriggered: axctlSubscribe.running = true
    }

    property int _reconnectAttempts: 0
    property real _reconnectBase: 1000

    function _scheduleReconnect() {
        root._reconnectAttempts++;
        var delay = Math.min(root._reconnectBase * Math.pow(2, Math.min(root._reconnectAttempts, 5)), 30000);
        reconnectTimer.interval = delay;
        reconnectTimer.restart();
        // Also try restarting the daemon if it died
        if (!axctlProcess.running && root._reconnectAttempts % 3 === 0) {
            axctlProcess.running = true;
        }
    }

    // Auto-reconnect on unexpected subscribe exit
    Timer {
        id: reconnectTimer
        interval: 1000
        onTriggered: axctlSubscribe.running = true
    }

    property Process axctlSubscribe: Process {
        command: ["axctl", "subscribe"]
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                if (!data || !data.trim()) return;
                // Skip non-JSON error messages from axctl
                if (!data.trim().startsWith("{")) return;
                try {
                    let parsedJson = JSON.parse(data);

                    // Apply inline state immediately (every event carries full state)
                    if (parsedJson.state) {
                        root.applyState(parsedJson.state);
                    }

                    // Emit raw event for consumers
                    parsedJson.name = parsedJson.method ? parsedJson.method.split('.').pop().toLowerCase() : "";
                    parsedJson.data = parsedJson.params;
                    root.rawEvent(parsedJson);
                } catch (e) {
                    console.warn("AxctlService subscribe JSON parse error:", e.message,
                                 "data:", data.substring(0, 100));
                }
            }
        }
        onExited: (code) => {
            console.warn("axctl subscribe exited:", code);
            root._scheduleReconnect();
        }
        onRunningChanged: {
            if (running) root._reconnectAttempts = 0;
        }
    }

    Component.onDestruction: {
        reconnectTimer.running = false
        axctlProcess.running = false
        axctlSubscribe.running = false
    }
}

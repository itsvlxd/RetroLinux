pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals

Singleton {
    id: root

    // ── Settings ──
    property bool enabled: false
    property bool systemdRunAvailable: false
    property bool dockerAvailable: false
    property int debounceDelay: 300
    property string dockerBinary: "docker"
    property string terminalApp: "kitty"
    property string shellPath: "/bin/sh"
    property int pollingInterval: 0
    property bool showPorts: true

    // ── State ──
    property var containers: []
    property int runningCount: 0
    property var composeProjects: []
    property string _inspectBuffer: ""

    // ── Tool checks ──
    property bool inputToolMissing: false

    Component.onCompleted: {
        loadSettings();
        initialize();
    }

    function loadSettings() {
        enabled = StateService.get("docker:enabled", false);
        dockerBinary = StateService.get("docker:dockerBinary", "docker");
        terminalApp = StateService.get("docker:terminalApp", "kitty");
        shellPath = StateService.get("docker:shellPath", "/bin/sh");
        debounceDelay = StateService.get("docker:debounceDelay", 300);
        pollingInterval = StateService.get("docker:pollingInterval", 0);
        showPorts = StateService.get("docker:showPorts", true);
    }

    function saveSetting(key, value) {
        if (key === "enabled") enabled = value;
        else if (key === "dockerBinary") dockerBinary = value;
        else if (key === "terminalApp") terminalApp = value;
        else if (key === "shellPath") shellPath = value;
        else if (key === "debounceDelay") debounceDelay = value;
        else if (key === "pollingInterval") pollingInterval = value;
        else if (key === "showPorts") showPorts = value;

        StateService.set("docker:" + key, value);
    }

    // ── Initialize ──

    function initialize() {
        systemdRunCheckProc.running = true;
        refresh();
        eventsProcess.running = true;
    }

    function refresh() {
        dockerInfoProc.running = true;
    }

    // ── Processes ──

    Process {
        id: systemdRunCheckProc
        command: ["which", "systemd-run"]
        running: false
        onExited: (code) => {
            root.systemdRunAvailable = (code === 0);
        }
    }

    Process {
        id: dockerInfoProc
        command: [root.dockerBinary, "info"]
        running: false
        onExited: (code) => {
            root.dockerAvailable = (code === 0);
            if (root.dockerAvailable) {
                fetchContainers();
            } else {
                updateContainers([], 0, []);
            }
        }
    }

    function fetchContainers() {
        dockerInspectProc.running = true;
    }

    Process {
        id: dockerInspectProc
        command: ["sh", "-c", root.dockerBinary + " container inspect $(" + root.dockerBinary + " container ls -aq 2>/dev/null) 2>/dev/null"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                root._inspectBuffer += data;
            }
        }
        onExited: (code) => {
            if (code === 0 && root._inspectBuffer.trim()) {
                try {
                    var parsed = JSON.parse(root._inspectBuffer.trim());
                    if (Array.isArray(parsed)) {
                        root._processContainers(parsed);
                    }
                } catch(e) {
                    console.error("[DockerService] Failed to parse inspect output:", e);
                    updateContainers([], 0, []);
                }
            } else {
                updateContainers([], 0, []);
            }
            root._inspectBuffer = "";
        }
    }

    // Re-parse: docker inspect outputs a JSON array as a single blob.
    // Use a bash wrapper to get it cleanly.
    function _processContainers(rawContainers) {
        try {
            var result = rawContainers.map(function(container) {
                try {
                    var labels = (container.Config && container.Config.Labels) || {};
                    var state = (container.State && container.State.Status) || "";
                    var startedAt = new Date((container.State && container.State.StartedAt) || 0).getTime();
                    var finishedAt = new Date((container.State && container.State.FinishedAt) || 0).getTime();
                    var lastActivity = Math.max(startedAt, finishedAt);

                    var ports = [];
                    var portBindings = (container.NetworkSettings && container.NetworkSettings.Ports) || {};
                    for (var containerPort in portBindings) {
                        var hostBindings = portBindings[containerPort];
                        if (hostBindings && hostBindings.length > 0) {
                            for (var j = 0; j < hostBindings.length; j++) {
                                var binding = hostBindings[j];
                                var hostPort = binding.HostPort;
                                var hostIp = binding.HostIp || "0.0.0.0";
                                if (hostPort) {
                                    ports.push({
                                        containerPort: containerPort,
                                        hostPort: hostPort,
                                        hostIp: hostIp
                                    });
                                }
                            }
                        }
                    }

                    return {
                        id: container.Id || "",
                        name: (container.Name || "").replace(/^\//, ""),
                        status: state.charAt(0).toUpperCase() + state.slice(1),
                        state: state,
                        image: (container.Config && container.Config.Image) || container.ImageName || "",
                        isRunning: (container.State && container.State.Running) || false,
                        isPaused: (container.State && container.State.Paused) || false,
                        created: container.Created || "",
                        lastActivity: lastActivity,
                        ports: ports,
                        composeProject: labels["com.docker.compose.project"] || labels["io.podman.compose.project"] || "",
                        composeService: labels["com.docker.compose.service"] || labels["io.podman.compose.service"] || "",
                        composeWorkingDir: labels["com.docker.compose.project.working_dir"] || "",
                        composeConfigFiles: labels["com.docker.compose.project.config_files"] || "compose.yaml"
                    };
                } catch (e) {
                    console.error("[DockerService] Failed to parse container:", e);
                    return null;
                }
            }).filter(function(c) { return c !== null; });

            // Sort: running first, then paused, then stopped; by lastActivity desc; then by name
            result.sort(function(a, b) {
                var priority = { running: 1, paused: 2 };
                var aP = priority[a.state] || 3;
                var bP = priority[b.state] || 3;
                if (aP !== bP) return aP - bP;
                if (a.lastActivity !== b.lastActivity) return b.lastActivity - a.lastActivity;
                return a.name.localeCompare(b.name);
            });

            // Build compose project map
            var projectMap = {};
            for (var i = 0; i < result.length; i++) {
                var c = result[i];
                if (c.composeProject) {
                    if (!projectMap[c.composeProject]) {
                        projectMap[c.composeProject] = {
                            name: c.composeProject,
                            containers: [],
                            runningCount: 0,
                            totalCount: 0,
                            workingDir: c.composeWorkingDir,
                            configFile: c.composeConfigFiles
                        };
                    }
                    projectMap[c.composeProject].containers.push(c);
                    projectMap[c.composeProject].totalCount++;
                    if (c.isRunning) {
                        projectMap[c.composeProject].runningCount++;
                    }
                }
            }

            var projects = Object.values(projectMap).sort(function(a, b) {
                if (a.runningCount !== b.runningCount) return b.runningCount - a.runningCount;
                return a.name.localeCompare(b.name);
            });

            var rc = 0;
            for (var j = 0; j < result.length; j++) {
                if (result[j].isRunning) rc++;
            }

            updateContainers(result, rc, projects);
        } catch (e) {
            console.error("[DockerService] Failed to process containers:", e);
            updateContainers([], 0, []);
        }
    }

    function updateContainers(containers, running, projects) {
        root.containers = containers || [];
        root.runningCount = running || 0;
        root.composeProjects = projects || [];
    }

    // ── Actions ──

    function executeAction(containerId, action) {
        var commands = {
            start: [dockerBinary, "start", containerId],
            stop: [dockerBinary, "stop", containerId],
            restart: [dockerBinary, "restart", containerId],
            pause: [dockerBinary, "pause", containerId],
            unpause: [dockerBinary, "unpause", containerId]
        };

        if (commands[action]) {
            var cmd = commands[action];
            if (systemdRunAvailable) {
                cmd = ["systemd-run", "--user", "--scope", "--"].concat(cmd);
            }
            Quickshell.execDetached(cmd);
            Qt.callLater(refresh);
            return true;
        }
        return false;
    }

    function executeComposeAction(workingDir, configFile, action) {
        if (!workingDir) {
            console.error("[DockerService] No working directory for compose action");
            return false;
        }

        var composeCommands = {
            up: [dockerBinary, "compose", "-f", configFile, "up", "-d"],
            down: [dockerBinary, "compose", "-f", configFile, "down"],
            restart: [dockerBinary, "compose", "-f", configFile, "restart"],
            stop: [dockerBinary, "compose", "-f", configFile, "stop"],
            start: [dockerBinary, "compose", "-f", configFile, "start"],
            pull: [dockerBinary, "compose", "-f", configFile, "pull"]
        };

        if (action === "logs") {
            var logCmd = 'cd "' + workingDir + '" && ' + dockerBinary + ' compose -f ' + configFile + ' logs -f';
            Quickshell.execDetached(["sh", "-c", terminalApp + " -e sh -c '" + logCmd + "'"]);
            return true;
        }

        if (composeCommands[action]) {
            var cmd = ["sh", "-c", 'cd "' + workingDir + '" && ' + composeCommands[action].join(" ")];
            if (systemdRunAvailable) {
                cmd = ["systemd-run", "--user", "--scope", "--"].concat(cmd);
            }
            Quickshell.execDetached(cmd);
            Qt.callLater(refresh);
            return true;
        }
        return false;
    }

    function openLogs(containerId) {
        Quickshell.execDetached(["sh", "-c", terminalApp + " -e " + dockerBinary + " logs -f " + containerId]);
    }

    function openExec(containerId) {
        Quickshell.execDetached(["sh", "-c", terminalApp + " -e " + dockerBinary + " exec -it " + containerId + " " + shellPath]);
    }

    // ── Events listener ──

    property var debounceTimer: Timer {
        interval: root.debounceDelay
        running: false
        repeat: false
        onTriggered: fetchContainers()
    }

    Process {
        id: eventsProcess
        command: [root.dockerBinary, "events", "--format", "json", "--filter", "type=container"]
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                try {
                    var event = JSON.parse(data);
                    var action = event.Status || event.status;
                    var known = ["start", "stop", "die", "died", "kill", "restart",
                                 "pause", "unpause", "create", "destroy", "remove", "cleanup"];
                    if (known.indexOf(action) >= 0) {
                        debounceTimer.restart();
                    }
                } catch (e) {
                    // ignore parse errors from partial lines
                }
            }
        }

        onRunningChanged: {
            if (!running) {
                restartTimer.start();
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 5000
        running: false
        repeat: false
        onTriggered: {
            if (root.dockerAvailable) {
                eventsProcess.running = true;
            }
        }
    }

    Timer {
        interval: root.pollingInterval
        running: root.dockerAvailable && root.pollingInterval > 0
        repeat: true
        onTriggered: fetchContainers()
    }

    onEnabledChanged: {
        if (enabled) {
            refresh();
            eventsProcess.running = true;
        } else {
            eventsProcess.running = false;
        }
    }
}

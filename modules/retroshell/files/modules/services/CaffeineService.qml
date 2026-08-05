import QtQuick
import Quickshell
import Quickshell.Io

pragma Singleton

Singleton {
    id: root

    property alias inhibit: idleInhibitor.enabled
    property int timedMinutes: 0
    property int initialMinutes: 0
    property var _endTime: 0
    property int _tick: 0

    readonly property int totalSecondsRemaining: {
        var tick = _tick;
        if (_endTime <= 0) return 0;
        return Math.max(0, Math.ceil((_endTime - Date.now()) / 1000));
    }

    readonly property string timeRemaining: {
        var tick = _tick;
        var total = totalSecondsRemaining;
        if (total <= 0) return "0:00";
        var min = Math.floor(total / 60);
        var sec = total % 60;
        return min + ":" + (sec < 10 ? "0" : "") + sec;
    }

    function toggleInhibit() {
        if (inhibit) {
            _cancelTimed();
            inhibit = false;
            _notify("Caffeine is off, your screen can now sleep");
        } else {
            _cancelTimed();
            inhibit = true;
            _notify("Caffeine is on, your screen will stay awake");
        }
    }

    function startTimed(minutes) {
        if (minutes > 0) {
            _endTime = Date.now() + minutes * 60000;
            timedMinutes = minutes;
            initialMinutes = minutes;
            _persistUntil();
            timedTimer.restart();
        } else {
            _cancelTimed();
        }
        if (!inhibit) {
            inhibit = true;
        }
        _notify(minutes > 0
            ? "Caffeine will keep your screen awake for " + minutes + " minute" + (minutes === 1 ? "" : "s")
            : "Caffeine is on, your screen will stay awake");
    }

    function _cancelTimed() {
        timedMinutes = 0;
        initialMinutes = 0;
        _endTime = 0;
        timedTimer.stop();
        _persistUntil();
    }

    function _persistUntil() {
        timedVarProcess.command = ["bash", "-c",
            'source "$RETRO_DIR/lib/variable.sh" && set_var CAFFEINE_UNTIL "' + _endTime + '" ' +
            '&& set_var CAFFEINE_INITIAL "' + initialMinutes + '"'];
        timedVarProcess.running = true;
    }

    function _readUntil() {
        readUntilProcess.command = ["bash", "-c",
            'source "$RETRO_DIR/lib/variable.sh" && echo "$(get_var CAFFEINE_UNTIL 0)|$(get_var CAFFEINE_INITIAL 0)"'];
        readUntilProcess.running = true;
    }

    function _notify(msg) {
        notifyProcess.command = ["notify-send", "-a", "RetroLinux", "Caffeine", msg];
        notifyProcess.running = true;
    }

    function _syncHypridle() {
        var value = root.inhibit ? "true" : "false";
        var extra = "";
        if (root.inhibit) {
            extra = " ; if pgrep -x hypridle >/dev/null 2>&1; then pkill -x hypridle; systemctl --user stop hypridle 2>/dev/null; fi";
        } else {
            extra = " ; [ \"$(get_var HYPRIDLE_ENABLE true)\" = \"true\" ] && ! pgrep -x hypridle >/dev/null 2>&1 && nohup hypridle -c \"${XDG_CONFIG_HOME:-$HOME/.config}/retro/hypridle.conf\" >/dev/null 2>&1 &";
        }
        caffeineVarProcess.command = ["bash", "-c",
            'source "$RETRO_DIR/lib/variable.sh" && set_var HYPRIDLE_CAFFEINE_ENABLE ' + value + extra];
        caffeineVarProcess.running = true;
    }

    Process {
        id: caffeineVarProcess
        running: false
        stdout: SplitParser {}
    }

    Process {
        id: timedVarProcess
        running: false
        stdout: SplitParser {}
    }

    Process {
        id: notifyProcess
        running: false
        stdout: SplitParser {}
    }

    Process {
        id: readUntilProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.trim().split("|");
                var end = parseInt(parts[0]);
                if (isNaN(end) || end <= 0)
                    return;
                if (end > Date.now()) {
                    root._endTime = end;
                    root.timedMinutes = Math.max(1, Math.ceil((end - Date.now()) / 60000));
                    var init = parseInt(parts[1]);
                    root.initialMinutes = isNaN(init) ? Math.max(1, Math.ceil((end - Date.now()) / 60000)) : Math.max(1, init);
                    if (!root.inhibit) {
                        root.inhibit = true;
                    }
                    timedTimer.restart();
                } else {
                    if (root.inhibit) {
                        root.inhibit = false;
                    }
                    root._cancelTimed();
                }
            }
        }
    }

    Timer {
        id: timedTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            root._tick++;
            if (root._endTime > 0 && Date.now() >= root._endTime) {
                root._cancelTimed();
                root.inhibit = false;
                root._notify("Caffeine session ended, your screen can now sleep");
                return;
            }
            if (root._endTime > 0) {
                root.timedMinutes = Math.max(1, Math.ceil((root._endTime - Date.now()) / 60000));
            }
        }
    }

    onInhibitChanged: {
        root._syncHypridle();
    }

    IdleInhibitor {
        id: idleInhibitor

        onEnabledChanged: {
            if (StateService.initialized) {
                StateService.set("caffeine", enabled);
            }
        }
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root.inhibit = StateService.get("caffeine", false);
            root._readUntil();
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: {
            if (StateService.initialized) {
                root.inhibit = StateService.get("caffeine", false);
            }
            root._readUntil();
        }
    }
}

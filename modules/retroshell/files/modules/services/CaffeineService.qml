import QtQuick
import Quickshell
import Quickshell.Io

pragma Singleton

Singleton {
    id: root

    property alias inhibit: idleInhibitor.enabled
    property int timedMinutes: 0
    property var _endTime: 0

    function toggleInhibit() {
        if (inhibit) {
            _cancelTimed();
            inhibit = false;
            _notify("Caffeine disabled — idle resumed");
        } else {
            _cancelTimed();
            inhibit = true;
            _notify("Caffeine enabled — system will not idle");
        }
    }

    function startTimed(minutes) {
        if (minutes > 0) {
            _endTime = Date.now() + minutes * 60000;
            timedMinutes = minutes;
            _persistUntil();
            timedTimer.restart();
        } else {
            _cancelTimed();
        }
        if (!inhibit) {
            inhibit = true;
        }
        _notify(minutes > 0
            ? "Caffeine enabled for " + minutes + " minute" + (minutes === 1 ? "" : "s")
            : "Caffeine enabled — system will not idle");
    }

    function _cancelTimed() {
        timedMinutes = 0;
        _endTime = 0;
        timedTimer.stop();
        _persistUntil();
    }

    function _persistUntil() {
        timedVarProcess.command = ["bash", "-c",
            'source "$RETRO_DIR/lib/variable.sh" && set_var CAFFEINE_UNTIL "' + _endTime + '"'];
        timedVarProcess.running = true;
    }

    function _readUntil() {
        readUntilProcess.command = ["bash", "-c",
            'source "$RETRO_DIR/lib/variable.sh" && get_var CAFFEINE_UNTIL "0"'];
        readUntilProcess.running = true;
    }

    function _notify(msg) {
        notifyProcess.command = ["notify-send", "-a", "retro", "-i", "caffeine", "Caffeine", msg];
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
                var end = parseInt(text.trim());
                if (isNaN(end) || end <= 0)
                    return;
                if (end > Date.now()) {
                    root._endTime = end;
                    root.timedMinutes = Math.max(1, Math.ceil((end - Date.now()) / 60000));
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
            if (root._endTime > 0 && Date.now() >= root._endTime) {
                root._cancelTimed();
                root.inhibit = false;
                root._notify("Caffeine expired — idle resumed");
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

import QtQuick
import Quickshell
import Quickshell.Io

pragma Singleton

Singleton {
    id: root

    property alias inhibit: idleInhibitor.enabled

    function toggleInhibit() {
        inhibit = !inhibit;
    }

    // Bridge caffeine state to the hypridle daemon watcher via a variable.
    // Caffeine ON  -> kills hypridle instantly if running and prevents restarts.
    // Caffeine OFF -> the daemon resumes normal hypridle management.
    function _syncHypridle() {
        var value = root.inhibit ? "true" : "false";
        var extra = "";
        if (root.inhibit) {
            extra = " ; if pgrep -x hypridle >/dev/null 2>&1; then pkill -x hypridle; systemctl --user stop hypridle 2>/dev/null; fi";
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
        }
    }
}
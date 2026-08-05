import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string retroCfg: Quickshell.env("RETRO_CONFIG") || Quickshell.env("HOME") + "/.config/retro"

    function get(key, callback) {
        getProc.command = ["bash", "-c", "source '" + retroCfg + "/variables.sh' 2>/dev/null; echo $" + key]
        getProc._callback = callback
        getProc.running = true
    }

    property Process getProc: Process {
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var cb = getProc._callback
                if (cb) cb(text.trim())
            }
        }
    }
}
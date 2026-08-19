import QtQuick
import Quickshell.Io

QtObject {
    id: root

    required property list<string> command

    property bool available: false

    property Process probeProcess: Process {
        command: root.command
        running: false
        onExited: exitCode => root.available = exitCode === 0
    }

    function recheck() {
        probeProcess.running = true
    }

    Component.onCompleted: probeProcess.running = true
}

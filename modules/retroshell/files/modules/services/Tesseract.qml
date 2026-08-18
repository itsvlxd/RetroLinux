pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.components

QtObject {
    id: root

    property CommandAvailability availability: CommandAvailability {
        command: ["bash", "-c", "command -v tesseract >/dev/null 2>&1"]
    }

    property bool available: availability.available

    function recheck() {
        availability.recheck()
    }
}

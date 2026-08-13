import QtQuick
import Quickshell
import qs.modules.components
import qs.modules.services
import qs.modules.theme
import Quickshell.Io

ActionGrid {
    id: root

    signal itemSelected

    layout: "row"
    buttonSize: 48
    iconSize: 20
    spacing: 8

    Process {
        id: actionProcess
        running: false
    }

    property string defaultLogoutCmd: "hyprctl dispatch 'hl.dsp.exit()'"

    Process {
        id: logoutDefaultReader
        running: true
        command: ["bash", "-c", "sed -n 's/^export RETRO_LOGOUT_CMD=\"\\(.*\\)\"$/\\1/p' \"${RETRO_DIR:-/opt/retrolinux}/modules/retro/files/variables.sh\" | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var val = text.trim()
                if (val) root.defaultLogoutCmd = val
            }
        }
    }

    Component.onCompleted: {
        root.forceActiveFocus();
    }

    actions: [
        {
            icon: Icons.lock,
            tooltip: "Lock Session",
            command: "retro shell lock"
        },
        {
            icon: Icons.suspend,
            tooltip: "Suspend",
            command: "systemctl suspend"
        },
        {
            icon: Icons.hibernate,
            tooltip: "Hibernate",
            command: "systemctl hibernate"
        },
        {
            icon: Icons.logout,
            tooltip: "Logout",
            command: (Quickshell.env("RETRO_LOGOUT_CMD") || root.defaultLogoutCmd)
        },
        {
            icon: Icons.reboot,
            tooltip: "Reboot",
            command: "systemctl reboot"
        },
        {
            icon: Icons.shutdown,
            tooltip: "Power Off",
            command: "systemctl poweroff"
        }
    ]

    onActionTriggered: action => {
        console.log("Action triggered:", action.command);
        if (action.command) {
            actionProcess.command = ["/bin/bash", "-c", action.command];
            console.log("Starting process with command:", actionProcess.command);
            actionProcess.running = true;
        }
        root.itemSelected();
    }
}

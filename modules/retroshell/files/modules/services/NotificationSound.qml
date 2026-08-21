pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services

/**
 * Plays notification sounds based on user preferences from notifications.json.
 * Reads soundEnabled, soundFile, and soundVolume from Config.notifications.
 */
Singleton {
    id: root

    // Sound asset directory
    readonly property string soundDir: Qt.resolvedUrl("../../../../assets/sound").toString().replace("file://", "")

    // Track the currently playing sound
    property bool isPlaying: false

    // Play a notification sound
    function playNotificationSound() {
        // Check if sounds are enabled
        if (!Config.notifications.soundEnabled) {
            return;
        }

        // Don't play if already playing
        if (isPlaying) {
            return;
        }

        const soundFile = Config.notifications.soundFile || "retro-default.mp3"
        const volume = Config.notifications.soundVolume || 40

        // Build full path to sound file
        const soundPath = soundDir + "/" + soundFile

        // Convert percentage volume to paplay format (0-65536)
        const paVol = Math.round(volume * 65536 / 100)

        isPlaying = true

        // Play using paplay (PulseAudio)
        soundProcess.command = ["paplay", "--volume", paVol.toString(), soundPath]
        soundProcess.running = true
    }

    Process {
        id: soundProcess
        onRunningChanged: {
            if (!running) {
                root.isPlaying = false
                if (exitCode !== 0) {
                    // Fallback to mpg123 for mp3 files
                    const soundFile = Config.notifications.soundFile || "retro-default.mp3"
                    if (soundFile.endsWith(".mp3")) {
                        const soundPath = root.soundDir + "/" + soundFile
                        const volume = Config.notifications.soundVolume || 40
                        fallbackProcess.command = ["mpg123", "-q", "--gain", volume.toString(), soundPath]
                        fallbackProcess.running = true
                    }
                }
            }
        }
    }

    Process {
        id: fallbackProcess
        onRunningChanged: {
            if (!running && exitCode !== 0) {
                console.log("NotificationSound: Failed to play sound")
            }
        }
    }

    // Connect to Notifications service notify signal
    Connections {
        target: Notifications
        function onNotify(notification) {
            // Only play sound for popup notifications (new, visible ones)
            if (notification && notification.popup) {
                root.playNotificationSound()
            }
        }
    }
}

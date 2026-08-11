pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool isListening: false
    property string currentSong: ""

    property bool _manuallyStopped: false

    function startListening() {
        if (root.isListening) return;
        root.isListening = true;
        root.currentSong = "";
        root._manuallyStopped = false;
        checkCommandProcess.running = true;
    }

    function stopListening() {
        root._manuallyStopped = true;
        recognizeProcess.running = false;
        root.isListening = false;
        root.currentSong = "";
    }

    function toggleListening() {
        if (root.isListening) {
            root.stopListening();
        } else {
            root.startListening();
        }
    }

    // Verify songrec + timeout exist before listening
    property Process checkCommandProcess: Process {
        id: checkCommandProcess
        command: ["bash", "-c", "command -v songrec >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1"]
        running: false
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.isListening = false;
                notifyMissingProcess.running = true;
            } else {
                notifyListeningProcess.running = true;
                recognizeProcess.running = true;
            }
        }
    }

    property Process notifyMissingProcess: Process {
        running: false
        command: ["notify-send", "-a", "RetroLinux", "-u", "critical", "Shazam", "songrec is not installed"]
    }

    property Process notifyListeningProcess: Process {
        running: false
        command: ["notify-send", "-a", "RetroLinux", "-t", "2500", "Shazam", "Listening for music..."]
    }

    // One-shot recognition: listens via mic until a song is matched (or the
    // 30s timeout). On a match it prints "Artist - Song" and exits by itself,
    // which makes the result arrive immediately and stops listening.
    property Process recognizeProcess: Process {
        id: recognizeProcess
        command: ["timeout", "30", "songrec", "recognize"]
        running: false

        stdout: StdioCollector {
            id: recognizeOut
        }

        onExited: exitCode => {
            console.log("[Shazam] recognize exited:", exitCode);
            var out = recognizeOut.text.trim();

            if (root._manuallyStopped) {
                root.isListening = false;
                root.currentSong = "";
                return;
            }

            root.isListening = false;
            root.currentSong = "";

            if (exitCode === 0 && out !== "") {
                root._onSong(out);
            } else if (exitCode === 124 || out === "") {
                notifyNoMatchProcess.running = true;
            } else {
                notifyErrorProcess.running = true;
            }
        }
    }

    property Process notifyNoMatchProcess: Process {
        running: false
        command: ["notify-send", "-a", "RetroLinux", "Shazam", "Couldn't recognize a song"]
    }

    property Process notifyErrorProcess: Process {
        running: false
        command: ["notify-send", "-a", "RetroLinux", "-u", "critical", "Shazam", "Shazam recognition failed"]
    }

    function _onSong(line) {
        var idx = line.indexOf(" - ");
        var song = idx > 0 ? line.substring(idx + 3) : line;
        var artist = idx > 0 ? line.substring(0, idx) : "";
        root.currentSong = line;
        root._notifySong(song, artist);
    }

    property Process notifySongProcess: Process {
        id: notifySongProcess
        running: false
        command: ["true"]
    }

    function _notifySong(song, artist) {
        var esc = s => String(s).replace(/'/g, "'\\''");
        notifySongProcess.command = ["bash", "-c",
            "action=$(notify-send -a RetroLinux -t 8000 -w 'Song Detected' '<b>" + esc(song) + "</b>\\nby <i>" + esc(artist) + "</i>' " +
            "-A 'youtube=Search YouTube' -A 'spotify=Search Spotify' 2>/dev/null); " +
            "if [[ \"$action\" == \"youtube\" ]]; then " +
            "q=$(printf '%s %s' '" + esc(artist) + "' '" + esc(song) + "' | jq -sRr @uri); " +
            "nohup xdg-open \"https://www.youtube.com/results?search_query=$q\" >/dev/null 2>&1 & " +
            "elif [[ \"$action\" == \"spotify\" ]]; then " +
            "q=$(printf '%s %s' '" + esc(artist) + "' '" + esc(song) + "' | jq -sRr @uri); " +
            "nohup xdg-open \"https://open.spotify.com/search/$q\" >/dev/null 2>&1 & fi"];
        notifySongProcess.running = true;
    }
}

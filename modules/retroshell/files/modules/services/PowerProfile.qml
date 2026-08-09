pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme

Singleton {
    id: root

    property var availableProfiles: ["power-saver", "balanced", "performance"]
    property string currentProfile: ""
    property bool isAvailable: true
    property string backendType: "retro" // Retro's native power engine (power_core.sh)

    signal profileChanged(string profile)

    Timer {
        id: startupDelay
        interval: 2000
        running: true
        onTriggered: initialize()
    }

    property bool _initialized: false

    function initialize() {
        if (_initialized) return;
        _initialized = true;
        console.info("PowerProfile: Using Retro native power engine (power_core.sh)");
        updateCurrentProfile();
    }

    Process {
        id: getProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var val = text.trim();
                if (!val) val = "balanced";
                var profile = "";
                if (val === "saver") profile = "power-saver";
                else if (val === "balanced") profile = "balanced";
                else if (val === "performance") profile = "performance";
                else profile = val;
                if (profile && profile !== currentProfile) {
                    console.info("PowerProfile: Current profile:", profile);
                    currentProfile = profile;
                    profileChanged(profile);
                }
            }
        }
    }

    Process {
        id: setProc
        running: false
        stdout: SplitParser {}
        stderr: SplitParser {
            onRead: data => {
                const err = data.trim();
                if (err && err.length > 0) {
                    console.warn("PowerProfile: Error:", err);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                console.info("PowerProfile: Profile changed successfully");
                Qt.callLater(() => {
                    updateCurrentProfile();
                });
            } else {
                console.warn("PowerProfile: Failed to set profile");
            }
        }
    }

    function updateCurrentProfile() {
        var retroDir = Quickshell.env("RETRO_DIR");
        getProc.command = ["bash", retroDir + "/scripts/power_core.sh", "--get"];
        getProc.running = true;
    }

    function updateAvailableProfiles() {
        console.info("PowerProfile: Available profiles:", availableProfiles);
    }

    function setProfile(profileName) {
        if (!isAvailable) {
            console.warn("PowerProfile: Cannot set profile - service not available");
            return;
        }

        let found = false;
        for (let i = 0; i < availableProfiles.length; i++) {
            if (availableProfiles[i] === profileName) {
                found = true;
                break;
            }
        }

        if (!found) {
            console.warn("PowerProfile: Profile not available:", profileName);
            return;
        }

        var retroProfile = profileName.replace("power-", "");
        console.info("PowerProfile: Setting profile to:", profileName, "→ retro", retroProfile);

        var retroDir = Quickshell.env("RETRO_DIR");
        setProc.command = ["bash", retroDir + "/scripts/power_core.sh", "--set", retroProfile];

        currentProfile = profileName;
        setProc.running = true;
    }

    function getProfileIcon(profileName) {
        if (profileName === "power-saver")
            return Icons.powerSave;
        if (profileName === "balanced")
            return Icons.balanced;
        if (profileName === "performance")
            return Icons.performance;
        return Icons.balanced;
    }

    function getProfileDisplayName(profileName) {
        if (profileName === "power-saver")
            return "Power Save";
        if (profileName === "balanced")
            return "Balanced";
        if (profileName === "performance")
            return "Performance";
        return profileName;
    }
}

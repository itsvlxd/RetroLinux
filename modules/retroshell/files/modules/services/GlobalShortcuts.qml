pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.globals
import qs.modules.services
import qs.config

import Quickshell.Io

QtObject {
    id: root

    readonly property string appId: "retroshell"
    readonly property string ipcPipe: "/tmp/retroshell_ipc.pipe"

    property Timer screenshotDelay: Timer {
        interval: 80
        repeat: false
        onTriggered: GlobalStates.screenshotToolVisible = true
    }

    // High-performance Pipe Listener (Daemon mode)
    property Process pipeListener: Process {
        command: ["bash", "-c", "rm -f " + root.ipcPipe + "; mkfifo " + root.ipcPipe + "; tail -f " + root.ipcPipe]
        running: true
        
        stdout: SplitParser {
            onRead: data => {
                const cmd = data.trim();
                if (cmd !== "") {
                    root.run(cmd);
                }
            }
        }
    }

    function run(command) {
        console.log("IPC run command received:", command);

        if (command.indexOf("wallpaper_ping ") === 0) {
            var path = command.substring("wallpaper_ping ".length).trim();
            if (path && GlobalStates.wallpaperManager) {
                GlobalStates.wallpaperManager.currentWallpaper = path;
                GlobalStates.wallpaperManager.syncConfigWall(path);
            }
            return;
        }

        switch (command) {
            // Launcher (Standalone Notch Module)
            case "launcher": toggleLauncher(); break;
            case "clipboard": toggleLauncherWithPrefix(1, Config.prefix.clipboard + " "); break;
            case "emoji": toggleLauncherWithPrefix(2, Config.prefix.emoji + " "); break;
            case "tmux": toggleLauncherWithPrefix(3, Config.prefix.tmux + " "); break;
            case "notes": toggleLauncherWithPrefix(4, Config.prefix.notes + " "); break;

            // Dashboard
            case "dashboard": toggleDashboardTab(0); break;
            case "wallpapers": toggleDashboardTab(1); break;
            case "assistant": toggleAssistant(); break;
            case "dashboard-widgets": toggleDashboardTab(0); break;
            case "dashboard-wallpapers": toggleDashboardTab(1); break;
            case "dashboard-kanban": toggleDashboardTab(2); break;
            case "dashboard-assistant": toggleAssistant(); break;
            case "dashboard-controls": toggleSettings(); break;

            // System
            case "overview": toggleSimpleModule("overview"); break;
            case "powermenu": toggleSimpleModule("powermenu"); break;
            case "tools": toggleSimpleModule("tools"); break;
            case "config": toggleSettings(); break;
            case "screenshot": Screenshot.initialize(); screenshotDelay.start(); break;
            case "screenrecord": ScreenRecorder.initialize(); GlobalStates.screenRecordToolVisible = true; break;
            case "lens": 
                Screenshot.initialize();
                Screenshot.captureMode = "lens";
                screenshotDelay.start();
                break;
            case "lockscreen": LockscreenService.lock(); break;
            case "brightness_ping": Brightness.refreshAll(); break;
            
            // Media
            case "media-seek-backward": seekActivePlayer(-mediaSeekStepMs); break;
            case "media-seek-forward": seekActivePlayer(mediaSeekStepMs); break;
            case "media-play-pause": 
                if (MprisController.canTogglePlaying) MprisController.togglePlaying();
                GlobalStates.mediaOsdAction = "play-pause";
                GlobalStates.mediaOsdVisible = true;
                break;
            case "media-next":
                MprisController.next();
                GlobalStates.mediaOsdAction = "next";
                GlobalStates.mediaOsdVisible = true;
                break;
            case "media-prev":
                MprisController.previous();
                GlobalStates.mediaOsdAction = "prev";
                GlobalStates.mediaOsdVisible = true;
                break;
                
            default: console.warn("Unknown IPC command:", command);
        }
    }

    property IpcHandler ipcHandler: IpcHandler {
        target: "retroshell"

        function run(command: string) {
            root.run(command);
        }
    }

    function toggleSettings(screenName) {
        Quickshell.execDetached(["retro", "settings"]);
    }

    function toggleSimpleModule(moduleName) {
        if (Visibilities.currentActiveModule === moduleName) {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule(moduleName);
        }
    }

    function toggleLauncher() {
        const isActive = Visibilities.currentActiveModule === "launcher";
        if (isActive && GlobalStates.widgetsTabCurrentIndex === 0 && GlobalStates.launcherSearchText === "") {
            Visibilities.setActiveModule("");
        } else {
            GlobalStates.widgetsTabCurrentIndex = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("launcher");
            }
        }
    }

    function toggleLauncherWithPrefix(tabIndex, prefix) {
        const isActive = Visibilities.currentActiveModule === "launcher";
        const currentTab = GlobalStates.widgetsTabCurrentIndex;
        const currentText = GlobalStates.launcherSearchText;

        if (isActive && currentTab === tabIndex && (currentText === prefix || currentText === "")) {
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        GlobalStates.widgetsTabCurrentIndex = tabIndex;
        GlobalStates.launcherSearchText = prefix;
        
        if (!isActive) {
            Visibilities.setActiveModule("launcher");
        }
    }

    function toggleDashboardTab(tabIndex) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        // Special handling for widgets tab (launcher)
        if (tabIndex === 0) {
            if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === "") {
                // Only toggle off if we're already in launcher without prefix
                Visibilities.setActiveModule("");
                return;
            }
            
            // Otherwise, always go to launcher (clear any prefix and ensure tab 0)
            GlobalStates.dashboardCurrentTab = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("dashboard");
            }
            return;
        }
        
        // For other tabs, normal toggle behavior
        if (isActive && GlobalStates.dashboardCurrentTab === tabIndex) {
            Visibilities.setActiveModule("");
            return;
        }

        GlobalStates.dashboardCurrentTab = tabIndex;
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
        }
    }

    function toggleDashboardWithPrefix(prefix) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === prefix) {
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        GlobalStates.dashboardCurrentTab = 0;
        
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
            Qt.callLater(() => {
                GlobalStates.launcherSearchText = prefix;
            });
        } else {
            GlobalStates.launcherSearchText = prefix;
        }
    }

    function toggleAssistant() {
        GlobalStates.toggleAssistant();
    }
    function seekActivePlayer(offset) {
        const player = MprisController.activePlayer;
        if (!player || !player.canSeek) {
            return;
        }

        const maxLength = typeof player.length === "number" && !isNaN(player.length)
                ? player.length
                : Number.MAX_SAFE_INTEGER;
        const clamped = Math.max(0, Math.min(maxLength, player.position + offset));
        player.position = clamped;
    }
}
